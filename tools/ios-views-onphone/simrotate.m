// Simulator-only: set an iOS simulator's device orientation with no Simulator.app.
// Build: clang -fobjc-arc -framework Foundation simrotate.m -o simrotate
// Usage: simrotate <udid> <1=portrait 2=upside-down 3=landscape-right 4=landscape-left>
// (UIDeviceOrientation values; device 4 is interface landscape-right.)
// Sends GSEventTypeDeviceOrientationChanged to the simulator's PurpleWorkspacePort.
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <objc/message.h>
#include <dlfcn.h>
int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc < 3) return 2;
    dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW);
    NSString* dev = @"/Applications/Xcode.app/Contents/Developer";
    id ctx = ((id(*)(id, SEL, id, NSError**))objc_msgSend)(
        NSClassFromString(@"SimServiceContext"),
        NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"), dev, nil);
    id set = ((id(*)(id, SEL, NSError**))objc_msgSend)(ctx, NSSelectorFromString(@"defaultDeviceSetWithError:"), nil);
    id device = nil;
    for (id d in [set valueForKey:@"devices"])
      if ([[[d valueForKey:@"UDID"] UUIDString] isEqual:@(argv[1])]) device = d;
    if (!device) { fprintf(stderr, "no device\n"); return 1; }
    NSError* err = nil;
    mach_port_t port = ((mach_port_t(*)(id, SEL, id, NSError**))objc_msgSend)(
        device, NSSelectorFromString(@"lookup:error:"), @"PurpleWorkspacePort", &err);
    if (!port) { fprintf(stderr, "no port %s\n", err.description.UTF8String); return 1; }
    uint8_t b[112] = {0};
    uint32_t* w = (uint32_t*)b;
    w[0x00/4] = 0x13; w[0x04/4] = 108; w[0x08/4] = port; w[0x14/4] = 0x7B;
    w[0x18/4] = 50 | 0x20000; w[0x48/4] = 4; w[0x4C/4] = (uint32_t)atoi(argv[2]);
    kern_return_t kr = mach_msg_send((mach_msg_header_t*)b);
    printf("sent orientation %s kr=%d\n", argv[2], kr);
    return kr == KERN_SUCCESS ? 0 : 1;
  }
}
