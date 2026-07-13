#include "console.h"
#include <stdio.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <errno.h>
#include <string.h>

static struct termios orig_termios;
static bool termios_saved = false;
static bool raw_mode_active = false;

bool console_enter_raw(void) {
    if (!isatty(STDIN_FILENO)) return false;

    if (tcgetattr(STDIN_FILENO, &orig_termios) != 0) {
        fprintf(stderr, "error: tcgetattr failed: %s\n", strerror(errno));
        return false;
    }
    termios_saved = true;

    struct termios raw = orig_termios;
    cfmakeraw(&raw);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) {
        fprintf(stderr, "error: tcsetattr failed: %s\n", strerror(errno));
        return false;
    }

    raw_mode_active = true;
    return true;
}

bool console_restore(void) {
    if (raw_mode_active && termios_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
        raw_mode_active = false;
    }
    return true;
}

static void sigwinch_handler(int sig) {
    (void)sig;
}

int console_bridge(int read_fd, int write_fd, bool (*should_stop)(void)) {
    if (read_fd < 0 || write_fd < 0) return -1;

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigwinch_handler;
    sigaction(SIGWINCH, &sa, NULL);

    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
        ioctl(read_fd, TIOCSWINSZ, &ws);
    }

    bool detach_sequence = false;

    while (!should_stop || !should_stop()) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(STDIN_FILENO, &fds);
        FD_SET(read_fd, &fds);

        int maxfd = read_fd > STDIN_FILENO ? read_fd : STDIN_FILENO;

        int ret = select(maxfd + 1, &fds, NULL, NULL, NULL);
        if (ret < 0) {
            if (errno == EINTR) {
                if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
                    ioctl(read_fd, TIOCSWINSZ, &ws);
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

                if (detach_sequence) {
                    detach_sequence = false;
                    if (c == 0x11) { // Ctrl+Q
                        goto done;
                    }
                    // Forward the previous Ctrl+P and this byte
                    unsigned char prev = 0x10;
                    write(write_fd, &prev, 1);
                    write(write_fd, &c, 1);
                    continue;
                }

                if (c == 0x10) { // Ctrl+P
                    detach_sequence = true;
                    continue;
                }

                write(write_fd, &c, 1);
            }
        }

        if (FD_ISSET(read_fd, &fds)) {
            char buf[4096];
            ssize_t n = read(read_fd, buf, sizeof(buf));
            if (n <= 0) break;

            ssize_t written = 0;
            while (written < n) {
                ssize_t w = write(STDOUT_FILENO, buf + written, n - written);
                if (w <= 0) break;
                written += w;
            }
        }
    }

done:
    console_restore();
    return 0;
}
