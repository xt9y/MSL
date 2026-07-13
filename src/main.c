#include "daemon.h"
#include "setup.h"
#include "state.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static void usage(void) {
    fprintf(stderr,
        "Usage: msl <command>\n"
        "\n"
        "Commands:\n"
        "  start               Boot or reattach to the Linux VM\n"
        "  stop                Shut down the Linux VM\n"
        "  status              Show VM state (running/stopped)\n"
        "  exec <command>      Run a command inside the VM\n"
        "  version             Show version information\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    const char *cmd = argv[1];

    if (strcmp(cmd, "start") == 0) {
        if (!setup_ensure()) return 1;
        return daemon_connect_console();
    }

    if (strcmp(cmd, "stop") == 0) {
        return daemon_send_stop();
    }

    if (strcmp(cmd, "status") == 0) {
        if (state_is_running()) {
            printf("running (pid %d)\n", state_get_daemon_pid());
            return 0;
        }
        printf("stopped\n");
        return 1;
    }

    if (strcmp(cmd, "exec") == 0) {
        if (argc < 3) {
            fprintf(stderr, "usage: msl exec <command> [args...]\n");
            return 1;
        }
        size_t len = 0;
        for (int i = 2; i < argc; i++) len += strlen(argv[i]) + 1;
        char *cmdline = malloc(len + 1);
        if (!cmdline) return 1;
        cmdline[0] = '\0';
        for (int i = 2; i < argc; i++) {
            if (i > 2) strcat(cmdline, " ");
            strcat(cmdline, argv[i]);
        }
        int rc = daemon_send_exec(cmdline);
        free(cmdline);
        return rc;
    }

    if (strcmp(cmd, "version") == 0) {
        printf("msl 1.0.0\n");
        printf("macOS Subsystem for Linux\n");
        return 0;
    }

    fprintf(stderr, "unknown command: %s\n\n", cmd);
    usage();
    return 1;
}
