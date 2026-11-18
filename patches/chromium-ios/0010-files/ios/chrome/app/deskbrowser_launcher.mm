// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/app/deskbrowser_launcher.h"

#import "content/app/ios/deskbrowser_builtin_jit.h"
#import "content/app/ios/deskbrowser_device_jit.h"
#import "content/app/ios/deskbrowser_settings.h"

#include <stdlib.h>
#include <string_view>

namespace {

NSString* const kStatusWaiting =
    @"Waiting for you to choose how to start.";
NSString* const kStatusStarting = @"Starting the built-in JIT helper…";
NSString* const kStatusAttached = @"Debugger attached. Enabling JIT…";
NSString* const kStatusOn = @"JIT is on. Chrome has not started yet.";
NSString* const kStatusFailed = @"Couldn't enable JIT.";
NSString* const kStatusJitFailed =
    @"JIT failed, running without JIT.";
NSString* const kStatusJitless = @"Starting without JIT.";

enum class LauncherPhase {
  kWaiting,
  kStarting,
  kAttached,
  kOn,
  kFailed,
  kJitless,
};

BOOL g_handed_off = NO;
BOOL g_started = NO;
void (^g_advance)(void) = nil;
id g_scene_observer = nil;
NSTimer* g_attach_timer = nil;
UIWindow* g_overlay = nil;

void StopAttachRetries();
void DismissLauncherOverlay();

}  // namespace

@interface DeskBrowserLauncherViewController : UIViewController
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UILabel* reasonLabel;
@property(nonatomic, strong) UIActivityIndicatorView* spinner;
@property(nonatomic, strong) UIButton* openButton;
@property(nonatomic, strong) UIButton* jitlessButton;
@property(nonatomic, strong) UISegmentedControl* tabCap;
@property(nonatomic, strong) UISegmentedControl* heapCap;
@property(nonatomic, strong) NSTimer* pollTimer;
@property(nonatomic, assign) CFAbsoluteTime deadline;
@property(nonatomic, assign) CFAbsoluteTime helperStart;
@property(nonatomic, assign) BOOL openChromeRequested;
@property(nonatomic, assign) BOOL jitMemoryFailed;
@property(nonatomic, assign) LauncherPhase phase;
@end

@implementation DeskBrowserLauncherViewController

- (instancetype)init {
  if ((self = [super init])) {
    _phase = LauncherPhase::kWaiting;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  UILabel* title = [[UILabel alloc] init];
  title.text = @"Chromium";
  title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  title.textColor = [UIColor labelColor];

  UILabel* subtitle = [[UILabel alloc] init];
  subtitle.text = @"JIT setup";
  subtitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
  subtitle.textAlignment = NSTextAlignmentCenter;
  subtitle.textColor = [UIColor secondaryLabelColor];

  _spinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.textColor = [UIColor labelColor];
  _statusLabel.numberOfLines = 0;

  _reasonLabel = [[UILabel alloc] init];
  _reasonLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
  _reasonLabel.textAlignment = NSTextAlignmentCenter;
  _reasonLabel.textColor = [UIColor secondaryLabelColor];
  _reasonLabel.numberOfLines = 0;

  UIStackView* statusRow = [[UIStackView alloc]
      initWithArrangedSubviews:@[ _spinner, _statusLabel ]];
  statusRow.axis = UILayoutConstraintAxisHorizontal;
  statusRow.alignment = UIStackViewAlignmentCenter;
  statusRow.spacing = 10;

  _openButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_openButton addTarget:self
                  action:@selector(openChrome)
        forControlEvents:UIControlEventTouchUpInside];

  _jitlessButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_jitlessButton addTarget:self
                     action:@selector(startWithoutJit)
           forControlEvents:UIControlEventTouchUpInside];

  UILabel* tabLabel = [self settingsCaption:@"Tabs kept in memory"];
  _tabCap = [[UISegmentedControl alloc] initWithItems:@[ @"2", @"4", @"6" ]];
  int tabs = DeskBrowserSettingTabCap();
  _tabCap.selectedSegmentIndex = (tabs >= 6 ? 2 : (tabs >= 4 ? 1 : 0));
  [_tabCap addTarget:self
                action:@selector(tabCapChanged)
      forControlEvents:UIControlEventValueChanged];

  UILabel* heapLabel = [self settingsCaption:@"V8 heap cap"];
  _heapCap = [[UISegmentedControl alloc]
      initWithItems:@[ @"256 MB", @"512 MB", @"1 GB" ]];
  int heap = DeskBrowserSettingMaxOldSpaceMb();
  _heapCap.selectedSegmentIndex = (heap >= 1024 ? 2 : (heap >= 512 ? 1 : 0));
  [_heapCap addTarget:self
                action:@selector(heapCapChanged)
      forControlEvents:UIControlEventValueChanged];

  UIStackView* settings = [[UIStackView alloc] initWithArrangedSubviews:@[
    tabLabel, _tabCap, heapLabel, _heapCap
  ]];
  settings.axis = UILayoutConstraintAxisVertical;
  settings.spacing = 8;
  settings.alignment = UIStackViewAlignmentFill;

  UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
    title, subtitle, statusRow, _reasonLabel, _openButton, _jitlessButton,
    settings
  ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 16;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [stack setCustomSpacing:24 afterView:subtitle];
  [stack setCustomSpacing:24 afterView:_reasonLabel];
  [stack setCustomSpacing:28 afterView:_jitlessButton];
  [self.view addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor
        constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
    [stack.trailingAnchor
        constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [_openButton.heightAnchor constraintEqualToConstant:50],
    [_jitlessButton.heightAnchor constraintEqualToConstant:44],
  ]];

  [self refreshUI];
}

- (UIButtonConfiguration*)primaryConfiguration:(NSString*)title {
  UIButtonConfiguration* c =
      [UIButtonConfiguration filledButtonConfiguration];
  c.title = title;
  c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
  c.buttonSize = UIButtonConfigurationSizeLarge;
  c.baseBackgroundColor = [UIColor systemBlueColor];
  c.baseForegroundColor = [UIColor whiteColor];
  c.titleTextAttributesTransformer = ^NSDictionary*(NSDictionary* incoming) {
    NSMutableDictionary* out = [incoming mutableCopy];
    out[NSFontAttributeName] =
        [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    return out;
  };
  return c;
}

- (UIButtonConfiguration*)secondaryConfiguration:(NSString*)title {
  UIButtonConfiguration* c =
      [UIButtonConfiguration grayButtonConfiguration];
  c.title = title;
  c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
  return c;
}

- (UILabel*)settingsCaption:(NSString*)text {
  UILabel* l = [[UILabel alloc] init];
  l.text = text;
  l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
  l.textColor = [UIColor secondaryLabelColor];
  return l;
}

- (NSString*)elapsedSuffix {
  if (_helperStart <= 0) {
    return @"";
  }
  int secs = (int)(CFAbsoluteTimeGetCurrent() - _helperStart);
  if (secs < 1) {
    return @"";
  }
  return [NSString stringWithFormat:@" (%ds)", secs];
}

- (void)refreshUI {
  if (!self.isViewLoaded) {
    return;
  }
  BOOL busy = (_phase == LauncherPhase::kStarting ||
               _phase == LauncherPhase::kAttached);
  if (busy) {
    [_spinner startAnimating];
    _spinner.hidden = NO;
  } else {
    [_spinner stopAnimating];
    _spinner.hidden = YES;
  }

  // Start without JIT must stay tappable even after "JIT is on".
  // Auto-continue used to disable this button and ignore the choice.
  _jitlessButton.configuration =
      [self secondaryConfiguration:@"Start without JIT"];
  _jitlessButton.enabled = !g_handed_off && _phase != LauncherPhase::kJitless;
  _openButton.enabled = !g_handed_off && _phase != LauncherPhase::kJitless;

  switch (_phase) {
    case LauncherPhase::kWaiting:
      _statusLabel.text = kStatusWaiting;
      _reasonLabel.text =
          @"Open Chrome starts the JIT helper. Start without JIT "
           "skips the helper and loads pages in jitless mode.";
      _openButton.configuration = [self primaryConfiguration:@"Open Chrome"];
      break;
    case LauncherPhase::kStarting:
      _statusLabel.text =
          [kStatusStarting stringByAppendingString:[self elapsedSuffix]];
      _reasonLabel.text =
          @"You can still tap Start without JIT to skip the helper.";
      _openButton.configuration = [self primaryConfiguration:@"Open Chrome"];
      break;
    case LauncherPhase::kAttached:
      _statusLabel.text =
          [kStatusAttached stringByAppendingString:[self elapsedSuffix]];
      _reasonLabel.text =
          @"You can still tap Start without JIT to skip JIT.";
      _openButton.configuration = [self primaryConfiguration:@"Open Chrome"];
      break;
    case LauncherPhase::kOn:
      _statusLabel.text = kStatusOn;
      _reasonLabel.text =
          @"Mode: JIT is available. Tap Open Chrome to use it, or Start "
           "without JIT to force jitless (recommended if Chrome froze).";
      _openButton.configuration = [self primaryConfiguration:@"Open Chrome"];
      break;
    case LauncherPhase::kFailed:
      if (_jitMemoryFailed) {
        _statusLabel.text = kStatusJitFailed;
        _reasonLabel.text =
            @"Could not reserve or prepare executable memory. Chrome will "
             "start in jitless mode.";
      } else {
        _statusLabel.text = kStatusFailed;
        {
          const char* notice = DeskBrowserJitFallbackNotice();
          _reasonLabel.text =
              notice ? @(notice)
                     : @"Leave LocalDevVPN on and confirm the pairing file is "
                       @"in Documents/StikJIT, then try again. You can still "
                       @"browse without JIT.";
        }
      }
      _openButton.configuration =
          [self primaryConfiguration:@"Open Chrome without JIT"];
      break;
    case LauncherPhase::kJitless:
      _statusLabel.text = kStatusJitless;
      _reasonLabel.text = @"Mode: jitless. The JIT helper will not be used.";
      _openButton.configuration =
          [self primaryConfiguration:@"Open Chrome without JIT"];
      break;
  }
}

- (void)tabCapChanged {
  NSArray<NSNumber*>* vals = @[ @2, @4, @6 ];
  NSInteger i = _tabCap.selectedSegmentIndex;
  if (i < 0 || i >= (NSInteger)vals.count) {
    return;
  }
  [[NSUserDefaults standardUserDefaults] setInteger:vals[i].integerValue
                                             forKey:@kDeskBrowserTabCapKey];
}

- (void)heapCapChanged {
  NSArray<NSNumber*>* vals = @[ @256, @512, @1024 ];
  NSInteger i = _heapCap.selectedSegmentIndex;
  if (i < 0 || i >= (NSInteger)vals.count) {
    return;
  }
  [[NSUserDefaults standardUserDefaults]
      setInteger:vals[i].integerValue
          forKey:@kDeskBrowserMaxOldSpaceMbKey];
}

- (void)startJit {
  if (DeskBrowserJitForceJitless() || _phase == LauncherPhase::kJitless) {
    NSLog(@"deskbrowser-jit: skipping helper, starting without JIT");
    [self startWithoutJit];
    return;
  }
  if (_phase == LauncherPhase::kStarting ||
      _phase == LauncherPhase::kAttached) {
    return;
  }
  if (DeskBrowserJitIsEnabled()) {
    [self markOn];
    return;
  }
  _helperStart = CFAbsoluteTimeGetCurrent();
  _deadline = _helperStart + 180;
  NSLog(@"deskbrowser-jit: user requested Open Chrome; starting helper");
  if (DeskBrowserJitDebuggerAttached() && DeskBrowserJitTryEnable()) {
    [self markOn];
    return;
  }
  if (!DeskBrowserJitStartBuiltInHelper()) {
    [self markFailed];
    return;
  }
  _phase = LauncherPhase::kStarting;
  [self refreshUI];
  if (_pollTimer) {
    return;
  }
  __weak DeskBrowserLauncherViewController* weakSelf = self;
  _pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                               repeats:YES
                                                 block:^(NSTimer*) {
                                                   [weakSelf poll];
                                                 }];
}

- (void)poll {
  if (_phase != LauncherPhase::kStarting &&
      _phase != LauncherPhase::kAttached) {
    return;
  }
  if (DeskBrowserJitForceJitless()) {
    [self startWithoutJit];
    return;
  }
  [self refreshUI];
  if (DeskBrowserJitDebuggerAttached()) {
    _phase = LauncherPhase::kAttached;
    [self refreshUI];
    if (DeskBrowserJitTryEnable()) {
      [self markOn];
      return;
    }
  }
  if (CFAbsoluteTimeGetCurrent() >= _deadline) {
    [self markFailed];
  }
}

- (void)fallbackToJitlessAfterProbeFail {
  _jitMemoryFailed = YES;
  _phase = LauncherPhase::kFailed;
  [_pollTimer invalidate];
  _pollTimer = nil;
  [self refreshUI];
  NSLog(@"deskbrowser-jit: JIT memory probe failed; will start without JIT");
  __weak DeskBrowserLauncherViewController* weakSelf = self;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [weakSelf startWithoutJit];
      });
}

- (BOOL)probeJitMemoryOrFallback {
  if (DeskBrowserJitForceJitless() || g_handed_off) {
    return NO;
  }
  if (DeskBrowserJitProbeBeforeV8()) {
    return YES;
  }
  [self fallbackToJitlessAfterProbeFail];
  return NO;
}

- (void)markOn {
  if (_phase == LauncherPhase::kOn || g_handed_off ||
      DeskBrowserJitForceJitless()) {
    return;
  }
  _phase = LauncherPhase::kOn;
  [_pollTimer invalidate];
  _pollTimer = nil;
  [self refreshUI];
  // Never auto-continue — a 0.6s timer used to start Chrome with JIT
  // before Start without JIT could be honored.
  NSLog(@"deskbrowser-jit: launcher JIT is on; waiting for tap");
  if (_openChromeRequested && !DeskBrowserJitForceJitless() && !g_handed_off) {
    NSLog(@"deskbrowser-jit: opening Chrome with JIT (user tapped Open Chrome)");
    if ([self probeJitMemoryOrFallback]) {
      [self handOff];
    }
  }
}

- (void)markFailed {
  if (_phase == LauncherPhase::kOn || _phase == LauncherPhase::kFailed ||
      _phase == LauncherPhase::kJitless || g_handed_off) {
    return;
  }
  _phase = LauncherPhase::kFailed;
  [_pollTimer invalidate];
  _pollTimer = nil;
  [self refreshUI];
  NSLog(@"deskbrowser-jit: launcher JIT failed: %s",
        DeskBrowserJitFallbackNotice() ? DeskBrowserJitFallbackNotice()
                                       : "(no notice)");
}

- (void)openChrome {
  if (g_handed_off || _phase == LauncherPhase::kJitless) {
    return;
  }
  _openChromeRequested = YES;
  if (DeskBrowserJitForceJitless() || _phase == LauncherPhase::kFailed) {
    [self startWithoutJit];
    return;
  }
  if (DeskBrowserJitIsEnabled()) {
    NSLog(@"deskbrowser-jit: opening Chrome with JIT (user tapped Open Chrome)");
    if ([self probeJitMemoryOrFallback]) {
      [self handOff];
    }
    return;
  }
  [self startJit];
}

- (void)startWithoutJit {
  if (g_handed_off) {
    return;
  }
  // Always honor this tap, even if the helper already attached or
  // the status says "JIT is on". Do not kill debugserver (that also
  // kills this process); just force jitless and skip further helper work.
  DeskBrowserJitSetForceJitless(true);
  _openChromeRequested = NO;
  _phase = LauncherPhase::kJitless;
  [_pollTimer invalidate];
  _pollTimer = nil;
  [self refreshUI];
  NSLog(@"deskbrowser-jit: user chose Start without JIT; forcing jitless and skipping helper");
  [self handOff];
}

- (void)handOff {
  if (g_handed_off) {
    return;
  }
  g_handed_off = YES;
  [_pollTimer invalidate];
  _pollTimer = nil;
  [self refreshUI];
  void (^advance)(void) = g_advance;
  g_advance = nil;
  NSLog(@"deskbrowser-jit: launcher handing off to Chrome (jit=%d)",
        DeskBrowserJitIsEnabled() && !DeskBrowserJitForceJitless());
  StopAttachRetries();
  DismissLauncherOverlay();
  if (advance) {
    advance();
  }
}

@end

namespace {

DeskBrowserLauncherViewController* g_controller = nil;

void DismissLauncherOverlay() {
  UIWindow* overlay = g_overlay;
  g_overlay = nil;
  if (!overlay) {
    return;
  }
  UIWindowScene* ws = overlay.windowScene;
  UIWindow* chrome = nil;
  if (ws) {
    for (UIWindow* candidate in ws.windows) {
      if (candidate && candidate != overlay) {
        chrome = candidate;
        break;
      }
    }
  }
  overlay.hidden = YES;
  overlay.rootViewController = nil;
  overlay.windowScene = nil;
  if (chrome) {
    [chrome makeKeyAndVisible];
  }
}

void PresentOnWindowScene(UIWindowScene* ws) {
  if (!ws || g_handed_off) {
    return;
  }
  if (!g_controller) {
    g_controller = [[DeskBrowserLauncherViewController alloc] init];
  }
  if (g_overlay && g_overlay.windowScene == ws) {
    g_overlay.rootViewController = g_controller;
    g_overlay.hidden = NO;
    [g_overlay makeKeyAndVisible];
    return;
  }
  if (g_overlay) {
    DismissLauncherOverlay();
  }
  // Dedicated overlay so Chrome can keep its official scene window
  // and AppInitStage can run past kStart. Torn down at handoff.
  UIWindow* overlay = [[UIWindow alloc] initWithWindowScene:ws];
  overlay.windowLevel = UIWindowLevelNormal + 1;
  overlay.backgroundColor = [UIColor systemBackgroundColor];
  overlay.rootViewController = g_controller;
  g_overlay = overlay;
  [overlay makeKeyAndVisible];
}

void PresentOnWindow(UIWindow* window) {
  if (!window || g_handed_off) {
    return;
  }
  UIWindowScene* ws = window.windowScene;
  if (ws) {
    PresentOnWindowScene(ws);
  }
}

void PresentOnConnectedScenes() {
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    PresentOnWindowScene((UIWindowScene*)scene);
    // One overlay is enough; the first connected scene is the
    // foreground launch scene on a phone.
    break;
  }
}

void EnsureSceneObserver() {
  if (g_scene_observer) {
    return;
  }
  g_scene_observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:UISceneDidActivateNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification*) {
                if (!g_handed_off) {
                  PresentOnConnectedScenes();
                }
              }];
}

void StopAttachRetries() {
  [g_attach_timer invalidate];
  g_attach_timer = nil;
  if (g_scene_observer) {
    [[NSNotificationCenter defaultCenter] removeObserver:g_scene_observer];
    g_scene_observer = nil;
  }
}

}  // namespace

extern "C" BOOL DeskBrowserLauncherShouldHold(void) {
  return g_started && !g_handed_off;
}

void DeskBrowserLauncherDeferAdvance(void (^advance)(void)) {
  if (!advance) {
    return;
  }
  if (!DeskBrowserLauncherShouldHold()) {
    advance();
    return;
  }
  g_advance = [advance copy];
}

void DeskBrowserLauncherAttachToWindow(UIWindow* window) {
  PresentOnWindow(window);
}

static bool EnvOrArgEnabled(const char* env_name, NSString* arg) {
  if (const char* env = getenv(env_name)) {
    const std::string_view value(env);
    if (!value.empty() && value != "0") {
      return true;
    }
  }
  for (NSString* process_arg in NSProcessInfo.processInfo.arguments) {
    if ([process_arg isEqualToString:arg]) {
      return true;
    }
  }
  return false;
}

static bool ForceJitlessRequested(void) {
  return EnvOrArgEnabled("DESKBROWSER_FORCE_JITLESS",
                         @"--deskbrowser-force-jitless");
}

// Hidden: off by default. When set, the JIT launcher overlay is shown
// and the built-in helper may be started. Icon taps do not set this.
static bool JitLauncherRequested(void) {
  if (EnvOrArgEnabled("DESKBROWSER_ENABLE_JIT_LAUNCHER",
                      @"--deskbrowser-enable-jit-launcher")) {
    return true;
  }
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:@"deskbrowser.enable_jit_launcher"];
}

void DeskBrowserLauncherStartIfNeeded(void) {
  if (g_handed_off) {
    return;
  }
  // Default path: jitless, no overlay, no helper. An icon tap goes
  // straight into Chrome. Keep the JIT launcher behind a hidden flag.
  if (!JitLauncherRequested()) {
    DeskBrowserJitSetForceJitless(true);
    NSLog(@"deskbrowser-jit: jitless default; skipping launcher and helper");
    return;
  }
  g_started = YES;
  if (ForceJitlessRequested()) {
    DeskBrowserJitSetForceJitless(true);
    NSLog(@"deskbrowser-jit: launcher force jitless (argv/env)");
  }
  NSLog(@"deskbrowser-jit: launcher overlay starting (hold V8 until handoff)");
  EnsureSceneObserver();
  PresentOnConnectedScenes();
  if (!g_controller) {
    g_controller = [[DeskBrowserLauncherViewController alloc] init];
  }
  // Do not start the helper until the user taps Open Chrome. Starting
  // it immediately made "JIT is on" auto-continue and ignored jitless.
  if (DeskBrowserJitForceJitless()) {
    [g_controller startWithoutJit];
  }
  if (!g_attach_timer && !g_handed_off) {
    g_attach_timer = [NSTimer
        scheduledTimerWithTimeInterval:0.05
                               repeats:YES
                                 block:^(NSTimer* timer) {
                                   if (g_handed_off) {
                                     [timer invalidate];
                                     return;
                                   }
                                   PresentOnConnectedScenes();
                                 }];
  }
}
