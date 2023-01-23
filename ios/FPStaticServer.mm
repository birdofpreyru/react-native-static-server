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
  // TODO: For now, let's just hardcode localhost IP, will do non-local support
  // later.
  resolve(@"localhost");
  /** THIS IS ANDROID/JAVA VERSION OF THE METHOD. CAN WE PORT IT TO IOS?
     try {
      Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces();
      while(en.hasMoreElements()) {
        NetworkInterface intf = en.nextElement();
        Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses();
        while(enumIpAddr.hasMoreElements()) {
          InetAddress inetAddress = enumIpAddr.nextElement();
          if (!inetAddress.isLoopbackAddress()) {
            String ip = inetAddress.getHostAddress();
            if(InetAddressUtils.isIPv4Address(ip)) {
              promise.resolve(ip);
              return;
            }
          }
        }
      }
      promise.resolve("localhost");
    } catch (Exception e) {
      promise.reject(e);
    }
  */
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
  int sockfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sockfd < 0) {
    reject(ERROR_DOMAIN, @"Error creating socket", NULL);
  }

  struct sockaddr_in serv_addr;
  memset(&serv_addr, 0, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  // INADDR_ANY is used to specify that the socket should be bound
  // to any available network interface.
  serv_addr.sin_addr.s_addr = htonl(INADDR_ANY);
  serv_addr.sin_port = 0;

  if (bind(sockfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
    reject(ERROR_DOMAIN, @"Error binding socket", NULL);
  }

  socklen_t len = sizeof(serv_addr);
  if (getsockname(sockfd, (struct sockaddr *) &serv_addr, &len) < 0) {
    reject(ERROR_DOMAIN, @"Error getting socket name", NULL);
  }
  int port = ntohs(serv_addr.sin_port);

  close(sockfd);
  resolve(@(port));
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
