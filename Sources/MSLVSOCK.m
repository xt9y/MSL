#import "MSLVSOCK.h"
#import <os/lock.h>

@interface MSLVSOCK ()
@property (strong, nullable) VZVirtioSocketDevice *socketDevice;
@end

@implementation MSLVSOCK {
    os_unfair_lock _connectLock;
}

- (instancetype)initWithConfiguration:(VZVirtualMachineConfiguration *)config {
    self = [super init];
    if (self) {
        VZVirtioSocketDeviceConfiguration *sockConfig = [[VZVirtioSocketDeviceConfiguration alloc] init];
        config.socketDevices = @[sockConfig];
        _connectLock = (os_unfair_lock){0};
    }
    return self;
}

- (void)setVM:(VZVirtualMachine *)vm {
    for (VZSocketDevice *dev in vm.socketDevices) {
        if ([dev isKindOfClass:[VZVirtioSocketDevice class]]) {
            self.socketDevice = (VZVirtioSocketDevice *)dev;
            return;
        }
    }
}

- (void)connectToPort:(uint32_t)port
           completion:(void (^)(void *socketHandle, int fd))completion
         errorHandler:(void (^)(NSError *error))errorHandler {
    if (!self.socketDevice) {
        errorHandler([NSError errorWithDomain:@"msl" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"VSOCK device not ready — VM may not be fully started"}]);
        return;
    }
    os_unfair_lock_lock(&_connectLock);
    [self.socketDevice connectToPort:port completionHandler:^(VZVirtioSocketConnection * _Nullable connection, NSError * _Nullable error) {
        os_unfair_lock_unlock(&_connectLock);
        if (connection) {
            void *handle = (void *)CFBridgingRetain(connection);
            completion(handle, connection.fileDescriptor);
        } else if (error) {
            errorHandler(error);
        } else {
            errorHandler([NSError errorWithDomain:@"msl" code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"VSOCK connection failed"}]);
        }
    }];
}

- (void)closeSocket:(void *)socketHandle {
    if (socketHandle) {
        VZVirtioSocketConnection *connection = (__bridge VZVirtioSocketConnection *)socketHandle;
        [connection close];
        CFBridgingRelease(socketHandle);
    }
}

@end
