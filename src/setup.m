#include "setup.h"
#include "state.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

#define KERNEL_FILENAME "kernel"
#define DISK_FILENAME "arch.img"

static const char *kernel_url =
    "https://github.com/xt9y/msl/releases/download/v1.0.0/kernel";

static const char *disk_url =
    "https://github.com/xt9y/msl/releases/download/v1.0.0/arch.img.gz";

static bool download_file(const char *url, const char *path) {
    char cmd[4096];
    int n = snprintf(cmd, sizeof(cmd),
                     "curl -Lsf -o \"%s\" \"%s\" 2>&1",
                     path, url);
    if (n >= (int)sizeof(cmd)) {
        fprintf(stderr, "error: URL too long\n");
        return false;
    }

    printf("  Downloading %s ...\n", url);
    fflush(stdout);

    int ret = system(cmd);
    if (ret != 0) {
        fprintf(stderr, "error: download failed (curl exit %d)\n", ret);
        return false;
    }

    struct stat st;
    if (stat(path, &st) != 0 || st.st_size == 0) {
        fprintf(stderr, "error: downloaded file is empty or missing\n");
        return false;
    }

    return true;
}

static bool decompress_gz(const char *gz_path, const char *out_path) {
    char cmd[4096];
    snprintf(cmd, sizeof(cmd), "gzip -d -c \"%s\" > \"%s\" 2>/dev/null", gz_path, out_path);
    printf("  Decompressing...\n");
    fflush(stdout);

    int ret = system(cmd);
    if (ret != 0) {
        fprintf(stderr, "error: decompression failed\n");
        return false;
    }

    struct stat st;
    if (stat(out_path, &st) != 0 || st.st_size == 0) {
        fprintf(stderr, "error: decompressed file is empty\n");
        return false;
    }

    unlink(gz_path);
    return true;
}

static bool file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && st.st_size > 0;
}

bool setup_ensure(void) {
    if (!state_init()) return false;

    const char *dir = state_dir();
    char kernel_path[1024];
    char disk_path[1024];

    snprintf(kernel_path, sizeof(kernel_path), "%s/%s", dir, KERNEL_FILENAME);
    snprintf(disk_path, sizeof(disk_path), "%s/%s", dir, DISK_FILENAME);

    bool need_kernel = !file_exists(kernel_path);
    bool need_disk = !file_exists(disk_path);

    if (!need_kernel && !need_disk) return true;

    printf("msl first-time setup\n");
    printf("Downloading Arch Linux ARM environment...\n\n");

    if (need_kernel) {
        if (!download_file(kernel_url, kernel_path)) return false;
        printf("  -> %s\n", kernel_path);
    }

    if (need_disk) {
        char gz_path[1024];
        snprintf(gz_path, sizeof(gz_path), "%s.gz", disk_path);
        if (!download_file(disk_url, gz_path)) return false;
        printf("  -> %s\n", gz_path);
        if (!decompress_gz(gz_path, disk_path)) return false;
        printf("  -> %s\n", disk_path);
    }

    printf("\nSetup complete.\n\n");
    return true;
}

const char *setup_kernel_path(void) {
    static char path[1024];
    snprintf(path, sizeof(path), "%s/%s", state_dir(), KERNEL_FILENAME);
    return path;
}

const char *setup_disk_path(void) {
    static char path[1024];
    snprintf(path, sizeof(path), "%s/%s", state_dir(), DISK_FILENAME);
    return path;
}
