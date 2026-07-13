#ifndef SETUP_H
#define SETUP_H

#include <stdbool.h>

bool setup_ensure(void);
const char *setup_kernel_path(void);
const char *setup_disk_path(void);

#endif
