#import "ReactNativeStaticServer.h"
#import "Server.h"
#import "Errors.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#include <net/if.h>

static NSString * const EVENT_NAME = @"RNStaticServer";
static dispatch_semaphore_t sem = dispatch_semaphore_create(1);

@implementation ReactNativeStaticServer {
    Server *server;
}

RCT_EXPORT_MODULE();

- (instancetype)init {
  return [super init];
}

- (void)invalidate
{
  [super invalidate];
  if (self->server) {
    [self stop:^void(id){}
      rejecter:^void(NSString *a,NSString *b, NSError *c){}];
  }
}

- (NSDictionary*) constantsToExport {
  return @{
    @"CRASHED": CRASHED,
    @"IS_MAC_CATALYST": @(TARGET_OS_MACCATALYST),
    @"LAUNCHED": LAUNCHED,
    @"TERMINATED": TERMINATED
  };
}

- (NSDictionary*) getConstants {
  return [self constantsToExport];
}

RCT_REMAP_METHOD(getLocalIpAddress,
  getLocalIpAddress:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
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
    [[RNException from:e] reject:reject];
  }
  @finally {
    freeifaddrs(interfaces);
  }
}

RCTPromiseResolveBlock pendingResolve = nil;
RCTPromiseRejectBlock pendingReject = nil;

RCT_REMAP_METHOD(start,
  start:(NSNumber* _Nonnull)serverId
  configPath:(NSString*)configPath
  errlogPath:(NSString*)errlogPath
  resolver:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
    NSLog(@"Starting the server...");

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (self->server) {
      auto e = [[RNException name:@"Another server instance is active"] log];
      [e reject:reject];
      dispatch_semaphore_signal(sem);
      return;
    }

    if (pendingResolve != nil || pendingReject != nil) {
      auto e = [[RNException name:@"Internal error"
                          details:@"Non-expected pending promise"] log];
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
        [self sendEventWithName:EVENT_NAME
          body: @{
            @"serverId": serverId,
            @"event": signal,
            @"details": details == nil ? @"" : details
          }
        ];
      } else {
        if (signal == CRASHED) {
          [[RNException name:@"Server crashed" details:details]
           reject:pendingReject];
        } else pendingResolve(details);
        pendingResolve = nil;
        pendingReject = nil;
        dispatch_semaphore_signal(sem);
      }
    };

    self->server = [Server
      serverWithConfig:configPath
      errlogPath:errlogPath
      signalConsumer:signalConsumer
    ];

    [self->server start];
}

- (NSArray<NSString *> *)supportedEvents {
  return @[EVENT_NAME];
}

RCT_REMAP_METHOD(stop,
  stop:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  try {
    if (self->server) {
      NSLog(@"Stopping...");

      dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

      if (pendingResolve != nil || pendingReject != nil) {
        auto e = [[RNException name:@"Internal error"
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
    [[RNException from:e] reject:reject];
  }
}

RCT_REMAP_METHOD(getOpenPort,
  address:(NSString*) address
  getOpenPort:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  @try {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
      [[RNException name:@"Error creating socket"] reject:reject];
      return;
    }

    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = 0;
    if (!inet_aton([address cStringUsingEncoding:NSUTF8StringEncoding], &(serv_addr.sin_addr))) {
      [[RNException name:@"Invalid address format"] reject:reject];
      return;
    }

    if (bind(sockfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
      [[RNException name:@"Error binding socket"] reject:reject];
      return;
    }

    socklen_t len = sizeof(serv_addr);
    if (getsockname(sockfd, (struct sockaddr *) &serv_addr, &len) < 0) {
      [[RNException name:@"Error getting socket name"] reject:reject];
      return;
    }
    int port = ntohs(serv_addr.sin_port);

    close(sockfd);
    resolve(@(port));
  }
  @catch (NSException *e) {
    [[RNException from:e] reject:reject];
  }
}

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

// Don't compile this code when we build for the old architecture.
#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeReactNativeStaticServerSpecJSI>(params);
}
#endif

@end
