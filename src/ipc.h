#ifndef IPC_H
#define IPC_H

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>

#define CMD_CONSOLE_ATTACH  0x01
#define CMD_CONSOLE_DETACH  0x02
#define CMD_EXEC            0x03
#define CMD_EXEC_RESULT     0x04
#define CMD_STOP            0x05
#define CMD_RESIZE          0x06

int  ipc_listen(const char *path);
int  ipc_connect(const char *path);
void ipc_close(int fd);
bool ipc_send_byte(int fd, uint8_t byte);
bool ipc_send_data(int fd, const void *data, size_t len);
bool ipc_recv_byte(int fd, uint8_t *byte);
bool ipc_recv_data(int fd, void *buf, size_t len);
int  ipc_recv_fd(int fd);

#endif
