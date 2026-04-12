#import "ReactNativeStaticServer.h"
#import "Server.h"
#import "Errors.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#include <net/if.h>

static dispatch_semaphore_t sem = dispatch_semaphore_create(1);

@implementation ReactNativeStaticServer {
    Server *server;
}

- (id) init {
  if (self = [super init]) {
    // The place to initialize properties.
  }
  return self;
}

- (void)invalidate
{
  if (self->server) {
    [self stop:^void(id){}
      reject:^void(NSString *a,NSString *b, NSError *c){}];
  }
}

- (facebook::react::ModuleConstants<JS::NativeReactNativeStaticServer::Constants>) constantsToExport {
  return facebook::react::typedConstants<JS::NativeReactNativeStaticServer::Constants>({
    .CRASHED = CRASHED,
    .IS_MAC_CATALYST = @(TARGET_OS_MACCATALYST),
    .LAUNCHED = LAUNCHED,
    .TERMINATED = TERMINATED
  });
}

- (facebook::react::ModuleConstants<JS::NativeReactNativeStaticServer::Constants>) getConstants {
  return [self constantsToExport];
}

- (void) getActiveServerId,
                 getActiveServerId:(RCTPromiseResolveBlock) resolve
                 reject:(RCTPromiseRejectBlock)reject
{
  resolve(self->server ? self->server.serverId : [NSNull null]);
}

- (void) getLocalIpAddress,
  getLocalIpAddress:(RCTPromiseResolveBlock)resolve
  reject:(RCTPromiseRejectBlock)reject
{
  struct ifaddrs *interfaces = NULL; // a linked list of network interfaces
  @try {
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces); // get the list of network interfaces
    if (success == 0) {
      NSLog(@"Found network interfaces, iterating.");
      temp_addr = interfaces;
      while(temp_addr != NULL) {
        // Check if the current interface is of type AF_INET (IPv4)
        // and not the loopback interface (lo0)
        if(temp_addr->ifa_addr->sa_family == AF_INET) {
          if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
            NSLog(@"Found IPv4 address of the local wifi connection. Returning address.");
            NSString *ip = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
            resolve(ip);
            return;
          }
        }
        temp_addr = temp_addr->ifa_next;
      }
    }
    NSLog(@"Could not find IP address, falling back to '127.0.0.1'.");
    resolve(@"127.0.0.1");
  }
  @catch (NSException *e) {
    [[RNSSException from:e] reject:reject];
  }
  @finally {
    freeifaddrs(interfaces);
  }
}

RCTPromiseResolveBlock pendingResolve = nil;
RCTPromiseRejectBlock pendingReject = nil;

- (void) start,
  start:(double)_serverId
  configPath:(NSString*)configPath
  errlogPath:(NSString*)errlogPath
  resolve:(RCTPromiseResolveBlock)resolve
  reject:(RCTPromiseRejectBlock)reject
{
    NSLog(@"Starting the server...");

    NSNumber *serverId = [NSNumber numberWithDouble:_serverId];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (self->server) {
      NSString *name = [NSString stringWithFormat:@"Failed to launch server #%@, another server instance (#%@) is active", serverId, self->server.serverId];
      auto e = [[RNSSException name:name] log];
      [e reject:reject];
      dispatch_semaphore_signal(sem);
      return;
    }

    if (pendingResolve != nil || pendingReject != nil) {
      NSString *name = [NSString stringWithFormat:@"Internal error (server #%@)", serverId];
      auto e = [[RNSSException name:name details:@"Non-expected pending promise"] log];
      [e reject:reject];
      dispatch_semaphore_signal(sem);
      return;
    }

    pendingResolve = resolve;
    pendingReject = reject;

    SignalConsumer signalConsumer = ^void(NSString * const signal,
                                          NSString * const details)
    {
      if (signal != LAUNCHED) self->server = nil;
      if (pendingResolve == nil && pendingReject == nil) {
        [self emitOnServerEvent: @{
            @"serverId": serverId,
            @"event": signal,
            @"details": details == nil ? @"" : details
          }
        ];
      } else {
        if (signal == CRASHED) {
          NSString *name = [NSString stringWithFormat:@"Server #%@ crashed", serverId];
          [[RNSSException name:name details:details]
           reject:pendingReject];
        } else pendingResolve(details);
        pendingResolve = nil;
        pendingReject = nil;
        dispatch_semaphore_signal(sem);
      }
    };

    self->server = [Server
      serverWithId:serverId
      configPath:configPath
      errlogPath:errlogPath
      signalConsumer:signalConsumer
    ];

    [self->server start];
}

- (void) stop,
  stop:(RCTPromiseResolveBlock)resolve
  reject:(RCTPromiseRejectBlock)reject
{
  try {
    if (self->server) {
      NSLog(@"Stopping...");

      dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

      if (pendingResolve != nil || pendingReject != nil) {
        auto e = [[RNSSException name:@"Internal error"
                            details:@"Unexpected pending promise"] log];
        [e reject:reject];
        dispatch_semaphore_signal(sem);
        return;
      }

      pendingResolve = resolve;
      pendingReject = reject;
      [self->server cancel];
    }
  } catch (NSException *e) {
    [[RNSSException from:e] reject:reject];
  }
}

- (void) getOpenPort,
  getOpenPort:(NSString*) address
  resolve:(RCTPromiseResolveBlock)resolve
  reject:(RCTPromiseRejectBlock)reject
{
  @try {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
      [[RNSSException name:@"Error creating socket"] reject:reject];
      return;
    }

    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = 0;
    if (!inet_aton([address cStringUsingEncoding:NSUTF8StringEncoding], &(serv_addr.sin_addr))) {
      [[RNSSException name:@"Invalid address format"] reject:reject];
      return;
    }

    if (bind(sockfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
      [[RNSSException name:@"Error binding socket"] reject:reject];
      return;
    }

    socklen_t len = sizeof(serv_addr);
    if (getsockname(sockfd, (struct sockaddr *) &serv_addr, &len) < 0) {
      [[RNSSException name:@"Error getting socket name"] reject:reject];
      return;
    }
    int port = ntohs(serv_addr.sin_port);

    close(sockfd);
    resolve(@(port));
  }
  @catch (NSException *e) {
    [[RNSSException from:e] reject:reject];
  }
}

- (void)addListener:(nonnull NSString *)eventName {}
- (void)removeListeners:(double)count {}

- (void) startObserving {
  // NOOP: Triggered when the first listener from JS side is added.
}

- (void) stopObserving {
  // NOOP: Triggered when the last listener from JS side is removed.
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeReactNativeStaticServerSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"ReactNativeStaticServer";
}

@end
