#include "daemon.h"
#include "runtime.h"
#include "vm.h"
#include "state.h"
#include "ipc.h"
#include "console.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <errno.h>

static vm_context_t vm_ctx;

static void pty_to_socket_bridge(int client_fd, int pty_fd) {
    bool active = true;
    while (active) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(client_fd, &fds);
        FD_SET(pty_fd, &fds);

        int maxfd = pty_fd > client_fd ? pty_fd : client_fd;
        int ret = select(maxfd + 1, &fds, NULL, NULL, NULL);

        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }

        if (FD_ISSET(client_fd, &fds)) {
            char buf[4096];
            ssize_t n = read(client_fd, buf, sizeof(buf));
            if (n <= 0) break;

            if ((unsigned char)buf[0] == CMD_RESIZE && n >= 5) {
                struct winsize ws;
                memset(&ws, 0, sizeof(ws));
                ws.ws_row = buf[1];
                ws.ws_col = buf[2];
                ioctl(pty_fd, TIOCSWINSZ, &ws);
                continue;
            }

            ssize_t written = 0;
            while (written < n) {
                ssize_t w = write(pty_fd, buf + written, n - written);
                if (w <= 0) break;
                written += w;
            }
        }

        if (FD_ISSET(pty_fd, &fds)) {
            char buf[16384];
            ssize_t n = read(pty_fd, buf, sizeof(buf));
            if (n <= 0) break;

            ssize_t written = 0;
            while (written < n) {
                ssize_t w = write(client_fd, buf + written, n - written);
                if (w <= 0) break;
                written += w;
            }
        }
    }
}

static void handle_exec(int client_fd) {
    uint32_t cmd_len = 0;
    if (!ipc_recv_data(client_fd, &cmd_len, 4)) return;
    cmd_len = ntohl(cmd_len);
    if (cmd_len > 65536 || cmd_len == 0) return;

    char *cmd = malloc(cmd_len + 1);
    if (!cmd) return;
    if (!ipc_recv_data(client_fd, cmd, cmd_len)) { free(cmd); return; }
    cmd[cmd_len] = '\0';

    char cwd[4096];
    const char *dir = getcwd(cwd, sizeof(cwd));
    if (!dir) dir = "";

    char full_cmd[16384];
    int n = snprintf(full_cmd, sizeof(full_cmd),
                     "cd '%s' 2>/dev/null; (%s); echo __MSL_EXIT:$?\n",
                     dir, cmd);
    free(cmd);

    if (n >= (int)sizeof(full_cmd)) {
        uint8_t resp = CMD_EXEC_RESULT;
        ipc_send_byte(client_fd, resp);
        uint32_t err = htonl(255), zero = 0;
        ipc_send_data(client_fd, &err, 4);
        ipc_send_data(client_fd, &zero, 4);
        return;
    }

    write(vm_ctx.pty_master_fd, full_cmd, strlen(full_cmd));

    char buf[4096];
    char outbuf[131072];
    size_t outpos = 0;
    int exit_code = 255;
    bool done = false;

    while (!done) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(vm_ctx.pty_master_fd, &fds);

        struct timeval tv = {30, 0};
        int ret = select(vm_ctx.pty_master_fd + 1, &fds, NULL, NULL, &tv);
        if (ret <= 0) break;

        ssize_t nr = read(vm_ctx.pty_master_fd, buf, sizeof(buf) - 1);
        if (nr <= 0) break;
        buf[nr] = '\0';

        char *marker = strstr(buf, "__MSL_EXIT:");
        if (marker) {
            exit_code = atoi(marker + 11);
            size_t off = marker - buf;
            if (off > 0 && outpos + off < sizeof(outbuf)) {
                memcpy(outbuf + outpos, buf, off);
                outpos += off;
            }
            done = true;
        } else {
            size_t remain = sizeof(outbuf) - outpos;
            size_t copy = (size_t)nr < remain ? (size_t)nr : remain;
            if (copy > 0) {
                memcpy(outbuf + outpos, buf, copy);
                outpos += copy;
            }
        }
    }

    uint8_t resp = CMD_EXEC_RESULT;
    ipc_send_byte(client_fd, resp);

    uint32_t net_exit = htonl(exit_code);
    ipc_send_data(client_fd, &net_exit, 4);

    uint32_t net_len = htonl((uint32_t)outpos);
    ipc_send_data(client_fd, &net_len, 4);
    if (outpos > 0) {
        ipc_send_data(client_fd, outbuf, outpos);
    }
}

int daemon_main(void) {
    setsid();
    chdir("/");

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);

    signal(SIGCHLD, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    vm_create(&vm_ctx);
    if (!vm_start(&vm_ctx)) {
        state_set_stopped();
        _exit(1);
    }

    state_set_running(getpid());

    unlink(state_socket_path());
    int listen_fd = ipc_listen(state_socket_path());
    if (listen_fd < 0) {
        vm_stop(&vm_ctx);
        state_set_stopped();
        _exit(1);
    }

    while (true) {
        struct sockaddr_un addr;
        socklen_t addr_len = sizeof(addr);
        int client_fd = accept(listen_fd, (struct sockaddr *)&addr, &addr_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            break;
        }

        uint8_t cmd;
        if (!ipc_recv_byte(client_fd, &cmd)) { close(client_fd); continue; }

        if (cmd == CMD_CONSOLE_ATTACH) {
            pty_to_socket_bridge(client_fd, vm_ctx.pty_master_fd);
            close(client_fd);
        } else if (cmd == CMD_EXEC) {
            handle_exec(client_fd);
            close(client_fd);
        } else if (cmd == CMD_STOP) {
            close(client_fd);
            break;
        } else {
            close(client_fd);
        }
        usleep(1000);
    }

    vm_stop(&vm_ctx);
    vm_destroy(&vm_ctx);
    close(listen_fd);
    unlink(state_socket_path());
    state_set_stopped();
    _exit(0);
    return 0;
}

int daemon_launch(void) {
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "error: fork failed: %s\n", strerror(errno));
        return -1;
    }
    if (pid == 0) {
        daemon_main();
        _exit(0);
    }

    for (int i = 0; i < 500; i++) {
        if (state_is_running()) return pid;
        usleep(10000);
    }
    return -1;
}

int daemon_connect_console(void) {
    if (!state_is_running()) {
        printf("Starting VM...\n");
        fflush(stdout);
        state_init();

        if (daemon_launch() < 0) {
            fprintf(stderr, "error: failed to start VM daemon\n");
            return 1;
        }
        printf("VM ready.\n");
    }

    int sock = ipc_connect(state_socket_path());
    if (sock < 0) {
        fprintf(stderr, "error: cannot connect to VM\n");
        return 1;
    }

    ipc_send_byte(sock, CMD_CONSOLE_ATTACH);

    bool raw = console_enter_raw();

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_IGN;
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);

    sa.sa_handler = SIG_IGN;
    sigaction(SIGWINCH, &sa, NULL);

    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
        uint8_t msg[5] = {CMD_RESIZE, ws.ws_row, ws.ws_col, 0, 0};
        write(sock, msg, 5);
    }

    bool active = true;
    bool prev_ctrl_p = false;

    while (active) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(STDIN_FILENO, &fds);
        FD_SET(sock, &fds);
        int maxfd = sock > STDIN_FILENO ? sock : STDIN_FILENO;
        int ret = select(maxfd + 1, &fds, NULL, NULL, NULL);

        if (ret < 0) {
            if (errno == EINTR) {
                if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
                    uint8_t msg[5] = {CMD_RESIZE, ws.ws_row, ws.ws_col, 0, 0};
                    write(sock, msg, 5);
                }
                continue;
            }
            break;
        }

        if (FD_ISSET(STDIN_FILENO, &fds)) {
            char buf[256];
            ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
            if (n <= 0) break;

            for (ssize_t i = 0; i < n; i++) {
                unsigned char c = (unsigned char)buf[i];
                if (prev_ctrl_p) {
                    prev_ctrl_p = false;
                    if (c == 0x11) { active = false; break; }
                    unsigned char p = 0x10;
                    write(sock, &p, 1);
                    write(sock, &c, 1);
                } else if (c == 0x10) {
                    prev_ctrl_p = true;
                } else {
                    write(sock, &c, 1);
                }
            }
        }

        if (FD_ISSET(sock, &fds)) {
            char buf[16384];
            ssize_t n = read(sock, buf, sizeof(buf));
            if (n <= 0) break;
            ssize_t written = 0;
            while (written < n) {
                ssize_t w = write(STDOUT_FILENO, buf + written, n - written);
                if (w <= 0) break;
                written += w;
            }
        }
    }

    if (raw) console_restore();
    close(sock);

    printf("\n[Detached — VM running in background. Use 'msl start' to reattach.]\n");
    return 0;
}

int daemon_send_exec(const char *cmdline) {
    if (!state_is_running()) {
        fprintf(stderr, "error: VM is not running\n");
        return 1;
    }

    int sock = ipc_connect(state_socket_path());
    if (sock < 0) {
        fprintf(stderr, "error: cannot connect to VM\n");
        return 1;
    }

    ipc_send_byte(sock, CMD_EXEC);

    size_t cmd_len = strlen(cmdline);
    uint32_t net_len = htonl((uint32_t)cmd_len);
    ipc_send_data(sock, &net_len, 4);
    ipc_send_data(sock, cmdline, cmd_len);

    uint8_t resp;
    if (!ipc_recv_byte(sock, &resp) || resp != CMD_EXEC_RESULT) {
        close(sock);
        return 1;
    }

    uint32_t exit_code_net;
    if (!ipc_recv_data(sock, &exit_code_net, 4)) { close(sock); return 1; }
    int exit_code = (int)ntohl(exit_code_net);

    uint32_t out_len_net;
    if (!ipc_recv_data(sock, &out_len_net, 4)) { close(sock); return exit_code; }
    uint32_t out_len = ntohl(out_len_net);

    if (out_len > 0) {
        char *out = malloc(out_len);
        if (out) {
            ipc_recv_data(sock, out, out_len);
            fwrite(out, 1, out_len, stdout);
            free(out);
        }
    }

    close(sock);
    return exit_code;
}

int daemon_send_stop(void) {
    if (!state_is_running()) {
        printf("VM is not running.\n");
        return 0;
    }

    int sock = ipc_connect(state_socket_path());
    if (sock >= 0) {
        ipc_send_byte(sock, CMD_STOP);
        close(sock);
    }

    for (int i = 0; i < 50; i++) {
        if (!state_is_running()) {
            printf("VM stopped.\n");
            return 0;
        }
        usleep(100000);
    }

    pid_t pid = state_get_daemon_pid();
    if (pid > 0) kill(pid, SIGTERM);
    state_set_stopped();
    printf("VM stopped.\n");
    return 0;
}
