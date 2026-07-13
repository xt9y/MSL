#include "vm.h"
#include "runtime.h"
#include "setup.h"
#include "state.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <util.h>
#include <dispatch/dispatch.h>
#include <errno.h>

static id vm_instance = NULL;

static id create_boot_loader(void) {
    const char *kernel_path = setup_kernel_path();
    if (!kernel_path) {
        fprintf(stderr, "error: kernel path not configured\n");
        return NULL;
    }

    id kernel_url = nsurl(kernel_path);
    if (!kernel_url) {
        fprintf(stderr, "error: failed to create kernel URL from %s\n", kernel_path);
        return NULL;
    }

    id bootloader = msg(cls("VZLinuxBootLoader"), "alloc");
    bootloader = msg(bootloader, "initWithKernelURL:", kernel_url);
    if (!bootloader) {
        fprintf(stderr, "error: failed to create Linux boot loader\n");
        return NULL;
    }

    const char *cmdline = "console=hvc0 root=/dev/vda rw loglevel=3";

    msg(bootloader, "setCommandLine:", nsstr(cmdline));

    return bootloader;
}

static id create_block_device(void) {
    const char *disk_path = setup_disk_path();
    if (!disk_path) {
        fprintf(stderr, "error: disk path not configured\n");
        return NULL;
    }

    id disk_url = nsurl(disk_path);
    if (!disk_url) return NULL;

    id attachment = msg(cls("VZDiskImageStorageDeviceAttachment"), "alloc");
    attachment = msg(attachment, "initWithURL:readOnly:", disk_url, false);
    if (!attachment) {
        fprintf(stderr, "error: failed to create disk image attachment\n");
        return NULL;
    }

    id block_dev = msg(cls("VZVirtioBlockDeviceConfiguration"), "alloc");
    if (!block_dev) return NULL;
    block_dev = msg(block_dev, "initWithAttachment:", attachment);

    return block_dev;
}

static id create_network_device(void) {
    id nat = msg(cls("VZNATNetworkDeviceAttachment"), "new");
    if (!nat) return NULL;

    id net_dev = msg(cls("VZVirtioNetworkDeviceConfiguration"), "new");
    if (!net_dev) return NULL;

    msg(net_dev, "setAttachment:", nat);
    return net_dev;
}

static id create_sharing_device(void) {
    id tag = nsstr("MacShare");

    id share_url = nsurl("/Users");
    if (!share_url) return NULL;

    id share = msg(cls("VZSharedDirectory"), "alloc");
    if (!share) return NULL;
    share = msg(share, "initWithURL:readOnly:", share_url, false);
    if (!share) return NULL;

    id fs = msg(cls("VZVirtioFileSystemDeviceConfiguration"), "alloc");
    if (!fs) return NULL;
    fs = msg(fs, "initWithTag:", tag);
    if (!fs) return NULL;

    id shares = msg(cls("NSArray"), "arrayWithObject:", share);

    id config = msg(cls("VZDirectorySharingConfiguration"),
                    "forGuestApplicationsWithAdditionalSharedDirectories:", shares);
    if (!config) {
        config = msg(cls("VZDirectorySharingConfiguration"), "forGuestApplications");
    }
    if (!config) return fs;

    msg(fs, "setDirectorySharing:", config);

    return fs;
}

static id create_serial_port(int slave_fd) {
    id read_handle = msg(cls("NSFileHandle"), "alloc");
    read_handle = msg(read_handle, "initWithFileDescriptor:closeOnDealloc:", slave_fd, true);

    id write_handle = msg(cls("NSFileHandle"), "alloc");
    write_handle = msg(write_handle, "initWithFileDescriptor:closeOnDealloc:", slave_fd, true);

    id attachment = msg(cls("VZFileHandleSerialPortAttachment"), "alloc");
    attachment = msg(attachment, "initWithFileHandleForReading:fileHandleForWriting:",
                     read_handle, write_handle);

    id serial = msg(cls("VZSerialPortConfiguration"), "new");
    msg(serial, "setAttachment:", attachment);

    return serial;
}

bool vm_create(vm_context_t *ctx) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->pty_master_fd = -1;
    ctx->pty_slave_fd = -1;
    return true;
}

bool vm_start(vm_context_t *ctx) {
    if (vm_instance) {
        NSInteger state = (NSInteger)msg(vm_instance, "state");
        if (state == 1) { // VZVirtualMachineStateRunning
            ctx->started = true;
            return true;
        }
    }

    id config = msg(cls("VZVirtualMachineConfiguration"), "new");
    if (!config) {
        fprintf(stderr, "error: failed to create VM configuration\n");
        return false;
    }

    id bootloader = create_boot_loader();
    if (!bootloader) return false;
    msg(config, "setBootLoader:", bootloader);

    msg(config, "setCPUCount:", (NSUInteger)2);
    msg(config, "setMemorySize:", (uint64_t)(2ULL * 1024 * 1024 * 1024));

    id block_dev = create_block_device();
    if (block_dev) {
        id devices = msg(cls("NSArray"), "arrayWithObject:", block_dev);
        msg(config, "setStorageDevices:", devices);
    }

    id net_dev = create_network_device();
    if (net_dev) {
        id devices = msg(cls("NSArray"), "arrayWithObject:", net_dev);
        msg(config, "setNetworkDevices:", devices);
    }

    id sharing_dev = create_sharing_device();
    if (sharing_dev) {
        id devices = msg(cls("NSArray"), "arrayWithObject:", sharing_dev);
        msg(config, "setDirectorySharingDevices:", devices);
    }

    int master_fd, slave_fd;
    if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) != 0) {
        fprintf(stderr, "error: failed to create PTY: %s\n", strerror(errno));
        return false;
    }

    ctx->pty_master_fd = master_fd;
    ctx->pty_slave_fd = slave_fd;

    id serial = create_serial_port(slave_fd);
    if (!serial) {
        close(master_fd);
        close(slave_fd);
        return false;
    }
    id ports = msg(cls("NSArray"), "arrayWithObject:", serial);
    msg(config, "setSerialPorts:", ports);

    id error = NULL;
    bool valid = msg(config, "validateWithError:", &error);
    if (!valid) {
        fprintf(stderr, "error: VM config validation failed: %s\n", err_desc(error));
        close(master_fd);
        close(slave_fd);
        return false;
    }

    vm_instance = msg(cls("VZVirtualMachine"), "alloc");
    vm_instance = msg(vm_instance, "initWithConfiguration:", config);
    if (!vm_instance) {
        fprintf(stderr, "error: failed to create VM instance\n");
        close(master_fd);
        close(slave_fd);
        return false;
    }

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block bool start_ok = false;

    void (^block)(id, NSError *) = ^(id self, NSError *err) {
        if (err) {
            fprintf(stderr, "error: VM start failed: %s\n", err_desc(err));
            start_ok = false;
        } else {
            start_ok = true;
        }
        dispatch_semaphore_signal(sem);
    };

    msg(vm_instance, "startWithCompletionHandler:", block);
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (!start_ok) {
        close(master_fd);
        close(slave_fd);
        return false;
    }

    ctx->started = true;
    printf("\033[2J\033[H");
    printf("Arch Linux ARM — msl\n");
    printf("\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\n\n");

    return true;
}

bool vm_stop(vm_context_t *ctx) {
    if (!vm_instance) return false;

    id error = NULL;
    bool ok = msg(vm_instance, "requestStopWithError:", &error);
    if (!ok) {
        fprintf(stderr, "warning: stop request failed: %s\n", err_desc(error));
    }

    for (int i = 0; i < 300; i++) {
        NSInteger state = (NSInteger)msg(vm_instance, "state");
        if (state == 0) break;
        usleep(100000);
    }

    NSInteger final_state = (NSInteger)msg(vm_instance, "state");
    vm_instance = NULL;

    if (ctx->pty_master_fd >= 0) {
        close(ctx->pty_master_fd);
        ctx->pty_master_fd = -1;
    }
    if (ctx->pty_slave_fd >= 0) {
        close(ctx->pty_slave_fd);
        ctx->pty_slave_fd = -1;
    }

    ctx->started = false;
    return final_state == 0;
}

void vm_destroy(vm_context_t *ctx) {
    vm_stop(ctx);
}
