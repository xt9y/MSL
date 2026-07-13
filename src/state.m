#include "state.h"
#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

static char state_dir_buf[1024];
static char socket_path[1024];
static char pid_path[1024];
static bool paths_initialized = false;

static void init_paths(void) {
    if (paths_initialized) return;
    const char *home = getenv("HOME");
    if (!home) home = "/tmp";
    snprintf(state_dir_buf, sizeof(state_dir_buf), "%s/.msl", home);
    snprintf(socket_path, sizeof(socket_path), "%s/.msl/daemon.sock", home);
    snprintf(pid_path, sizeof(pid_path), "%s/.msl/daemon.pid", home);
    paths_initialized = true;
}

const char *state_dir(void) { init_paths(); return state_dir_buf; }
const char *state_socket_path(void) { init_paths(); return socket_path; }
const char *state_pid_path(void) { init_paths(); return pid_path; }

bool state_init(void) {
    init_paths();
    struct stat st;
    if (stat(state_dir_buf, &st) != 0) {
        if (mkdir(state_dir_buf, 0755) != 0) {
            fprintf(stderr, "error: failed to create %s: %s\n", state_dir_buf, strerror(errno));
            return false;
        }
    }
    return true;
}

bool state_set_running(pid_t daemon_pid) {
    init_paths();
    FILE *f = fopen(pid_path, "w");
    if (!f) {
        fprintf(stderr, "error: failed to write pid file: %s\n", strerror(errno));
        return false;
    }
    fprintf(f, "%d\n", (int)daemon_pid);
    fclose(f);
    return true;
}

bool state_set_stopped(void) {
    init_paths();
    if (unlink(pid_path) != 0 && errno != ENOENT) {
        fprintf(stderr, "error: failed to remove pid file: %s\n", strerror(errno));
        return false;
    }
    return true;
}

bool state_is_running(void) {
    init_paths();
    FILE *f = fopen(pid_path, "r");
    if (!f) return false;

    pid_t pid = 0;
    fscanf(f, "%d", (int *)&pid);
    fclose(f);

    if (pid <= 0) return false;

    if (kill(pid, 0) == 0) return true;

    state_set_stopped();
    return false;
}

pid_t state_get_daemon_pid(void) {
    init_paths();
    FILE *f = fopen(pid_path, "r");
    if (!f) return -1;
    pid_t pid = 0;
    fscanf(f, "%d", (int *)&pid);
    fclose(f);
    return pid;
}
