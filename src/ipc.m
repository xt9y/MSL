#include "ipc.h"
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>

int ipc_listen(const char *path) {
    unlink(path);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "error: socket creation failed: %s\n", strerror(errno));
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "error: bind failed: %s\n", strerror(errno));
        close(fd);
        return -1;
    }

    chmod(path, 0700);

    if (listen(fd, 5) < 0) {
        fprintf(stderr, "error: listen failed: %s\n", strerror(errno));
        close(fd);
        return -1;
    }

    return fd;
}

int ipc_connect(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    return fd;
}

void ipc_close(int fd) {
    if (fd >= 0) close(fd);
}

bool ipc_send_byte(int fd, uint8_t byte) {
    return write(fd, &byte, 1) == 1;
}

bool ipc_send_data(int fd, const void *data, size_t len) {
    const uint8_t *ptr = (const uint8_t *)data;
    size_t remaining = len;
    while (remaining > 0) {
        ssize_t n = write(fd, ptr, remaining);
        if (n <= 0) return false;
        ptr += n;
        remaining -= n;
    }
    return true;
}

bool ipc_recv_byte(int fd, uint8_t *byte) {
    return read(fd, byte, 1) == 1;
}

bool ipc_recv_data(int fd, void *buf, size_t len) {
    uint8_t *ptr = (uint8_t *)buf;
    size_t remaining = len;
    while (remaining > 0) {
        ssize_t n = read(fd, ptr, remaining);
        if (n <= 0) return false;
        ptr += n;
        remaining -= n;
    }
    return true;
}

int ipc_recv_fd(int fd) {
    (void)fd;
    return -1;
}
