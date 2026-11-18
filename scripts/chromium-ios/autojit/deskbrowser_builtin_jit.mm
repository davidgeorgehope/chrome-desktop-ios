// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "content/app/ios/deskbrowser_builtin_jit.h"

#include <TargetConditionals.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

#import "content/app/ios/deskbrowser_device_jit.h"

// Private NSExtension entry points, looked up by class name so this
// file does not link a private SDK stub. Must be at file scope.
@interface NSObject (DeskBrowserNSExtension)
+ (id)extensionWithIdentifier:(NSString*)identifier error:(NSError**)error;
- (void)beginExtensionRequestWithInputItems:(NSArray*)items
                                 completion:(void (^)(NSUUID*))completion;
- (void)setRequestCompletionBlock:(void (^)(NSUUID*, NSArray*))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID*, NSError*))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID*))block;
@end

namespace {

char g_notice[512];
bool g_has_notice = false;

void SetNotice(NSString* msg) {
  if (!msg.length) {
    g_has_notice = false;
    g_notice[0] = 0;
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:@"deskbrowser.jit.fallback_notice"];
    return;
  }
  NSLog(@"deskbrowser-jit: %@", msg);
  if (![msg getCString:g_notice
             maxLength:sizeof(g_notice)
              encoding:NSUTF8StringEncoding]) {
    g_notice[sizeof(g_notice) - 1] = 0;
  }
  g_has_notice = true;
  [[NSUserDefaults standardUserDefaults]
      setObject:msg
         forKey:@"deskbrowser.jit.fallback_notice"];
}

NSString* PairingFilePath() {
  NSString* docs = NSSearchPathForDirectoriesInDomains(
                       NSDocumentDirectory, NSUserDomainMask, YES)
                       .firstObject;
  return [[docs stringByAppendingPathComponent:@"StikJIT"]
      stringByAppendingPathComponent:@"pairingFile.plist"];
}

NSData* ReadPairingFile() {
  NSString* path = PairingFilePath();
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return nil;
  }
  return [NSData dataWithContentsOfFile:path];
}

// Starts the helper and returns immediately. enableJIT in the helper
// process stays blocked while the universal script is attached; we do
// not wait for that request to finish. The pairing bytes are passed in
// the request and never logged. The NSExtension is CFRetained for the
// process lifetime so a mid-attach release cannot drop the debugger.
bool StartHelper(NSData* pairing) {
  NSURL* url = [[NSBundle mainBundle].builtInPlugInsURL
      URLByAppendingPathComponent:@"DeskBrowserJITHelper.appex"];
  NSString* identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
  if (!identifier) {
    SetNotice(@"The built-in JIT helper is missing from this install.");
    return false;
  }
  Class extensionClass = NSClassFromString(@"NSExtension");
  if (!extensionClass) {
    dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/"
           "ExtensionFoundation",
           RTLD_NOW);
    extensionClass = NSClassFromString(@"NSExtension");
  }
  if (!extensionClass) {
    SetNotice(@"iOS has no way to start the built-in JIT helper.");
    return false;
  }
  NSError* error = nil;
  id extension = [extensionClass extensionWithIdentifier:identifier
                                                   error:&error];
  if (!extension) {
    SetNotice(@"iOS would not find the built-in JIT helper.");
    return false;
  }
  CFRetain((__bridge CFTypeRef)extension);
  [extension setRequestCompletionBlock:^(NSUUID*, NSArray*){
  }];
  [extension setRequestCancellationBlock:^(NSUUID*, NSError*) {
    NSLog(@"deskbrowser-jit: helper request cancelled");
  }];
  [extension setRequestInterruptionBlock:^(NSUUID*) {
    NSLog(@"deskbrowser-jit: helper request interrupted");
  }];
  NSExtensionItem* item = [NSExtensionItem new];
  item.userInfo = @{@"pid" : @((int)getpid()), @"pairing" : pairing};
  [extension beginExtensionRequestWithInputItems:@[ item ]
                                      completion:^(NSUUID* requestID) {
                                        if (!requestID) {
                                          NSLog(@"deskbrowser-jit: iOS would "
                                                @"not start the JIT helper");
                                        }
                                      }];
  return true;
}

bool WaitForDebugger(CFTimeInterval seconds) {
  const CFTimeInterval deadline = CFAbsoluteTimeGetCurrent() + seconds;
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    if (DeskBrowserJitDebuggerAttached()) {
      return DeskBrowserJitTryEnable();
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, true);
  }
  return DeskBrowserJitDebuggerAttached() && DeskBrowserJitTryEnable();
}

}  // namespace

extern "C" const char* DeskBrowserJitFallbackNotice(void) {
  return g_has_notice ? g_notice : nullptr;
}

extern "C" bool DeskBrowserJitEnableWithBuiltInHelper(void) {
#if TARGET_OS_SIMULATOR || !TARGET_OS_IOS
  return false;
#else
  DeskBrowserJitInstallTrapHandler();
  if (DeskBrowserJitTryEnable()) {
    return true;
  }
  NSData* pairing = ReadPairingFile();
  if (!pairing.length) {
    SetNotice(@"Chrome needs the same pairing file crate uses, at "
              @"Documents/StikJIT/pairingFile.plist, and LocalDevVPN "
              @"turned on. It will run without JIT until then.");
    return false;
  }
  if (!StartHelper(pairing)) {
    if (!g_has_notice) {
      SetNotice(@"The built-in JIT helper could not start. Chrome will "
                @"run without JIT.");
    }
    return false;
  }
  // First launch may download Apple's developer disk image through the
  // helper; later launches are much quicker.
  if (WaitForDebugger(180)) {
    SetNotice(nil);
    return true;
  }
  SetNotice(@"Built-in JIT didn't attach in time. Leave LocalDevVPN on "
            @"and confirm the pairing file is in Documents/StikJIT, then "
            @"relaunch. Chrome will run without JIT this time.");
  return false;
#endif
}
