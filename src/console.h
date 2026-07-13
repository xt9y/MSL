#ifndef CONSOLE_H
#define CONSOLE_H

#include <stdbool.h>

bool console_enter_raw(void);
bool console_restore(void);
int  console_bridge(int read_fd, int write_fd, bool (*should_stop)(void));

#endif
