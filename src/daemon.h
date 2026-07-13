#ifndef DAEMON_H
#define DAEMON_H

#include <stdbool.h>

int  daemon_main(void);
int  daemon_launch(void);
int  daemon_connect_console(void);
int  daemon_send_exec(const char *cmdline);
int  daemon_send_stop(void);

#endif
