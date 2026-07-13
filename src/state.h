#ifndef STATE_H
#define STATE_H

#include <stdbool.h>
#include <unistd.h>

const char *state_dir(void);
const char *state_socket_path(void);
const char *state_pid_path(void);

bool state_init(void);
bool state_set_running(pid_t daemon_pid);
bool state_set_stopped(void);
bool state_is_running(void);
pid_t state_get_daemon_pid(void);

#endif
