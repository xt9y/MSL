#ifndef VM_H
#define VM_H

#include <stdbool.h>
#include <dispatch/dispatch.h>

typedef struct {
    int  pty_master_fd;
    int  pty_slave_fd;
    bool started;
} vm_context_t;

bool vm_create(vm_context_t *ctx);
bool vm_start(vm_context_t *ctx);
bool vm_stop(vm_context_t *ctx);
void vm_destroy(vm_context_t *ctx);

#endif
