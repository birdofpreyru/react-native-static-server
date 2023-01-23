#import "FPStaticServer.h"
#import "Server.h"

static NSString * const ERROR_DOMAIN = @"RNStaticServer";
static NSString * const EVENT_NAME = @"RNStaticServer";

@implementation RNStaticServer {
    Server *server;
}

RCT_EXPORT_MODULE(StaticServer);

- (instancetype)init {
  return [super init];
}

- (void)dealloc {
  if (self->server) {
    [self->server cancel];
  }
}

- (NSDictionary*) constantsToExport {
  return @{
    @"CRASHED": CRASHED,
    @"LAUNCHED": LAUNCHED,
    @"TERMINATED": TERMINATED
  };
}

RCT_EXPORT_METHOD(
  getLocalIpAddress:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  struct ifaddrs *interfaces = NULL; // a linked list of network interfaces
  struct ifaddrs *temp_addr = NULL;
  int success = getifaddrs(&interfaces); // get the list of network interfaces
  if (success == 0) {
    NSLog(@"Found network interfaces, iterating.");
    temp_addr = interfaces;
    while(temp_addr != NULL) {
      // Check if the current interface is of type AF_INET (IPv4)
      // and not the loopback interface (lo0)
      if(temp_addr->ifa_addr->sa_family == AF_INET) {
        if(!(temp_addr->ifa_flags & IFF_LOOPBACK)) {
          NSLog(@"Found IPv4 & non-loopback interface. Retrieving IP address.");
          NSString *ip = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
          resolve(ip);
          freeifaddrs(interfaces);
          return;
        }
      }
      temp_addr = temp_addr->ifa_next;
    }
  }
  NSLog(@"Could not find IP address, falling back to localhost.");
  resolve(@"localhost");
  freeifaddrs(interfaces);
}

RCT_EXPORT_METHOD(
  isRunning:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  resolve(@(self->server && self->server.executing));
}

RCT_EXPORT_METHOD(
  start:(NSNumber* _Nonnull)serverId
  configPath:(NSString*)configPath
  resolver:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
    NSLog(@"Starting the server...");

    if (self->server) {
      NSString *msg = @"Another server instance is active";
      NSError *e = [NSError
        errorWithDomain:ERROR_DOMAIN
        code:1
        userInfo:NULL
      ];
      NSLog(@"%@", msg);
      reject(e.domain, msg, e);
      return;
    }

    __block BOOL settled = false;
    SignalConsumer signalConsumer = ^void(NSString * const signal) {
      if (!settled) {
        settled = true;
        if (signal == LAUNCHED) {
          NSLog(@"SERVER LAUNCHED!");
          resolve(NULL);
        }
        else reject(ERROR_DOMAIN, @"Launch failure", NULL);
      }
      [self sendEventWithName:EVENT_NAME
        body: @{
          @"serverId": serverId,
          @"event": signal
        }
      ];
    };

    self->server = [Server
      serverWithConfig:configPath
      signalConsumer:signalConsumer
    ];

    [self->server start];
}

- (NSArray<NSString *> *)supportedEvents {
  return @[EVENT_NAME];
}

RCT_EXPORT_METHOD(
  stop:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  try {
    if (self->server) {
      NSLog(@"Stopping...");
      [self->server cancel];
      // TODO: In Java we do server.join() here to wait for server thread to exit,
      // can't find counterpart of .join() for NSThread. Probably, there is
      // another way to do it, and we should use it.
      self->server = NULL;
      NSLog(@"Stopped");
      resolve(NULL);
    }
  } catch (NSException *e) {
    NSString *msg = @"Failed to stop";
    NSLog(msg);
    reject(e.name, msg, NULL);
  }
}

RCT_EXPORT_METHOD(
  getOpenPort:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject
) {
  // TODO: For now, let's just hardcode this port, we'll implement the actual
  // open port detection later.
  resolve(@(3000));
/**
ANDROID/JAVA IMPLEMENTATION OF THE METHOD
try {
      ServerSocket socket = new ServerSocket(0);
      int port = socket.getLocalPort();
      socket.close();
      promise.resolve(port);
    } catch (Exception e) {
      promise.reject(e);
    }
*/
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

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeStaticServerSpecJSI>(params);
}
#endif

@end
