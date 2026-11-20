// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/views/ios/views_trackpad_ios.h"

#import <GameController/GameController.h>

#include <algorithm>
#include <cmath>

#include "base/time/time.h"
#include "ui/display/screen.h"
#include "ui/events/event.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/dom/dom_code.h"
#include "ui/events/keycodes/dom/dom_key.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/geometry/point.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/vector2d.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/native_widget_ios.h"

// Implemented by content's RenderWidgetUIView (see
// render_widget_host_view_ios_uiview.mm, "DeskBrowser external-display
// input"). Declared here so the host does not depend on content internals.
@protocol ChromeViewsIOSWebInput <NSObject>
- (void)deskBrowserInjectMouseAtViewPoint:(CGPoint)point
                                     type:(NSInteger)type
                                   button:(NSInteger)button;
- (void)deskBrowserInjectWheelAtViewPoint:(CGPoint)point
                                    delta:(CGPoint)delta
                                    phase:(NSInteger)phase;
- (void)insertText:(NSString*)text;
- (void)deleteBackward;
@optional
- (BOOL)deskBrowserAcceptsInput;
// modifiers: 1 Shift, 2 Control, 4 Alt, 8 Meta.
- (void)deskBrowserInjectKeyWithWindowsKeyCode:(NSInteger)windowsKeyCode
                                       domCode:(NSInteger)domCode
                                        domKey:(NSInteger)domKey
                                          text:(unichar)text
                                     modifiers:(NSInteger)modifiers;
@end

namespace {

constexpr CGFloat kCursorGain = 2.5;  // Phone points to external points.
constexpr CGFloat kScrollGain = 3.0;
// A hardware mouse (GCMouse) reports raw counts; this maps them to external
// screen points at a comfortable desktop speed.
constexpr CGFloat kMouseGain = 1.0;
// One wheel notch (GCMouse scroll value 1.0) in Chrome wheel pixels.
constexpr CGFloat kWheelNotch = 40.0;
// Max time and distance between clicks of one double/triple click.
constexpr double kMultiClickSeconds = 0.5;
constexpr CGFloat kMultiClickSlop = 4.0;

struct KeyMapping {
  ui::KeyboardCode code;
  ui::DomCode dom_code;
  ui::DomKey dom_key;
  unichar text;
};

// Keys sent to web content as real key events (keydown/keypress/keyup), so
// pages see them. Typed text and Backspace keep the text-input path.
bool WebKeyForHIDUsage(UIKeyboardHIDUsage usage, KeyMapping* out) {
  switch (usage) {
    case UIKeyboardHIDUsageKeyboardReturnOrEnter:
      *out = {ui::VKEY_RETURN, ui::DomCode::ENTER, ui::DomKey::ENTER, '\r'};
      return true;
    case UIKeyboardHIDUsageKeypadEnter:
      *out = {ui::VKEY_RETURN, ui::DomCode::NUMPAD_ENTER, ui::DomKey::ENTER,
              '\r'};
      return true;
    case UIKeyboardHIDUsageKeyboardTab:
      *out = {ui::VKEY_TAB, ui::DomCode::TAB, ui::DomKey::TAB, '\t'};
      return true;
    case UIKeyboardHIDUsageKeyboardEscape:
      *out = {ui::VKEY_ESCAPE, ui::DomCode::ESCAPE, ui::DomKey::ESCAPE, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardLeftArrow:
      *out = {ui::VKEY_LEFT, ui::DomCode::ARROW_LEFT, ui::DomKey::ARROW_LEFT,
              0};
      return true;
    case UIKeyboardHIDUsageKeyboardRightArrow:
      *out = {ui::VKEY_RIGHT, ui::DomCode::ARROW_RIGHT,
              ui::DomKey::ARROW_RIGHT, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardUpArrow:
      *out = {ui::VKEY_UP, ui::DomCode::ARROW_UP, ui::DomKey::ARROW_UP, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardDownArrow:
      *out = {ui::VKEY_DOWN, ui::DomCode::ARROW_DOWN, ui::DomKey::ARROW_DOWN,
              0};
      return true;
    case UIKeyboardHIDUsageKeyboardPageUp:
      *out = {ui::VKEY_PRIOR, ui::DomCode::PAGE_UP, ui::DomKey::PAGE_UP, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardPageDown:
      *out = {ui::VKEY_NEXT, ui::DomCode::PAGE_DOWN, ui::DomKey::PAGE_DOWN, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardHome:
      *out = {ui::VKEY_HOME, ui::DomCode::HOME, ui::DomKey::HOME, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardEnd:
      *out = {ui::VKEY_END, ui::DomCode::END, ui::DomKey::END, 0};
      return true;
    case UIKeyboardHIDUsageKeyboardDeleteForward:
      *out = {ui::VKEY_DELETE, ui::DomCode::DEL, ui::DomKey::DEL, 0};
      return true;
    default:
      return false;
  }
}

NSInteger WebModifiersForUIFlags(int flags) {
  NSInteger m = 0;
  if (flags & ui::EF_SHIFT_DOWN) {
    m |= 1;
  }
  if (flags & ui::EF_CONTROL_DOWN) {
    m |= 2;
  }
  if (flags & ui::EF_ALT_DOWN) {
    m |= 4;
  }
  if (flags & ui::EF_COMMAND_DOWN) {
    m |= 8;
  }
  return m;
}

NSString* const kTrackpadHint =
    @"Trackpad\nOne finger: move · Tap: click\nTwo fingers: scroll · "
    @"Two-finger tap: right-click";
NSString* const kConnectDisplayHint =
    @"Chrome Desktop\nConnect a monitor to use desktop Chrome.\nThis phone "
    @"then becomes its trackpad and keyboard.";

UIWindowScene* ExternalScene() {
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) {
      continue;
    }
    if (![scene.session.role
            isEqualToString:UIWindowSceneSessionRoleApplication] &&
        scene.activationState != UISceneActivationStateUnattached) {
      return static_cast<UIWindowScene*>(scene);
    }
  }
  return nil;
}

bool IsWidgetWindow(UIWindow* window) {
  return views::NativeWidgetIOS::GetFromNativeWindow(
             gfx::NativeWindow(window)) != nullptr;
}

// Widget windows on |scene|, front to back.
NSArray<UIWindow*>* WidgetWindowsFrontToBack(UIWindowScene* scene) {
  NSMutableArray<UIWindow*>* windows = [NSMutableArray array];
  for (UIWindow* window in scene.windows.reverseObjectEnumerator) {
    if (!window.hidden && window.alpha > 0 && IsWidgetWindow(window)) {
      [windows addObject:window];
    }
  }
  return [windows sortedArrayWithOptions:NSSortStable
                         usingComparator:^NSComparisonResult(UIWindow* a,
                                                             UIWindow* b) {
                           if (a.windowLevel == b.windowLevel) {
                             return NSOrderedSame;
                           }
                           return a.windowLevel > b.windowLevel
                                      ? NSOrderedAscending
                                      : NSOrderedDescending;
                         }];
}

bool IsWebInputView(UIView* v) {
  return [v respondsToSelector:@selector
            (deskBrowserInjectMouseAtViewPoint:type:button:)];
}

bool AcceptsWebInput(UIView* v) {
  return IsWebInputView(v) &&
         (![v respondsToSelector:@selector(deskBrowserAcceptsInput)] ||
          [(id<ChromeViewsIOSWebInput>)v deskBrowserAcceptsInput]);
}

id<ChromeViewsIOSWebInput> WebInputForView(UIView* view) {
  for (UIView* v = view; v; v = v.superview) {
    if (IsWebInputView(v)) {
      return AcceptsWebInput(v) ? static_cast<id<ChromeViewsIOSWebInput>>(v)
                                : nil;
    }
  }
  return nil;
}

// Front-most active web view under |point| (window coordinates). Hidden
// prerender/background RenderWidget views can sit above the active page.
UIView* FindAcceptingWebView(UIView* root, CGPoint point_in_window) {
  if (root.hidden || root.alpha <= 0.01) {
    return nil;
  }
  for (UIView* child in root.subviews.reverseObjectEnumerator) {
    if (UIView* found = FindAcceptingWebView(child, point_in_window)) {
      return found;
    }
  }
  if (AcceptsWebInput(root)) {
    CGPoint p = [root convertPoint:point_in_window fromView:nil];
    if ([root pointInside:p withEvent:nil]) {
      return root;
    }
  }
  return nil;
}

ui::KeyboardCode KeyCodeForCharacter(unichar c) {
  if (c >= 'a' && c <= 'z') {
    return static_cast<ui::KeyboardCode>(ui::VKEY_A + (c - 'a'));
  }
  if (c >= 'A' && c <= 'Z') {
    return static_cast<ui::KeyboardCode>(ui::VKEY_A + (c - 'A'));
  }
  if (c >= '0' && c <= '9') {
    return static_cast<ui::KeyboardCode>(ui::VKEY_0 + (c - '0'));
  }
  switch (c) {
    case ' ':
      return ui::VKEY_SPACE;
    case '.':
      return ui::VKEY_OEM_PERIOD;
    case '/':
      return ui::VKEY_OEM_2;
    case '-':
      return ui::VKEY_OEM_MINUS;
    default:
      return ui::VKEY_UNKNOWN;
  }
}

}  // namespace

@implementation ChromeViewsIOSTrackpadView {
  UIWindow* _cursorWindow;
  CAShapeLayer* _cursorLayer;
  CGPoint _cursor;  // In external screen points.
  BOOL _cursorPlaced;
  // Keyboard target: the last clicked web view, or the last clicked widget
  // window when the click landed on Views UI.
  __weak UIView* _keyWebView;
  __weak UIWindow* _keyWidgetWindow;
  __weak UIWindow* _hoverWindow;
  CGPoint _lastPan;
  CGPoint _lastScroll;
  UILabel* _hint;
  UIButton* _keyboardButton;
  // Hardware keys need first responder; an empty input view keeps the
  // on-screen keyboard down until the keyboard button asks for it.
  UIView* _emptyInputView;
  BOOL _softKeyboard;
  // Hardware mouse. GCMouse gives relative motion that is not clamped to the
  // phone screen, plus buttons and the wheel. The phone-side pointer (hover,
  // indirect clicks, scroll gestures) is the fallback when GameController
  // delivers nothing; it is ignored while GCMouse is active.
  NSMutableSet<GCMouse*>* _mice;
  CFTimeInterval _gcMouseLastEvent;
  int _mouseButtons;  // ui::EF_*_MOUSE_BUTTON flags held down.
  __weak UIView* _pressWebView;
  __weak UIWindow* _pressWindow;
  CFTimeInterval _lastClickTime;
  CGPoint _lastClickPoint;
  int _lastClickButton;
  int _clickCount;
  CGPoint _lastHover;
  BOOL _hoverValid;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) {
    return nil;
  }
  self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
  self.multipleTouchEnabled = YES;
  _emptyInputView = [[UIView alloc] initWithFrame:CGRectZero];

  _hint = [[UILabel alloc] init];
  _hint.text = kConnectDisplayHint;
  _hint.numberOfLines = 0;
  _hint.textAlignment = NSTextAlignmentCenter;
  _hint.textColor = [UIColor colorWithWhite:0.55 alpha:1];
  _hint.font = [UIFont systemFontOfSize:15];
  _hint.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:_hint];
  [NSLayoutConstraint activateConstraints:@[
    [_hint.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [_hint.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_hint.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor
                                               constant:-32],
  ]];

  UIButton* keyboard = [UIButton buttonWithType:UIButtonTypeSystem];
  _keyboardButton = keyboard;
  keyboard.hidden = YES;
  [keyboard setImage:[UIImage systemImageNamed:@"keyboard"]
            forState:UIControlStateNormal];
  keyboard.tintColor = [UIColor colorWithWhite:0.75 alpha:1];
  keyboard.translatesAutoresizingMaskIntoConstraints = NO;
  [keyboard addTarget:self
                action:@selector(toggleKeyboard)
      forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:keyboard];
  [NSLayoutConstraint activateConstraints:@[
    [keyboard.trailingAnchor
        constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor
                       constant:-16],
    [keyboard.bottomAnchor
        constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor
                       constant:-16],
    [keyboard.widthAnchor constraintEqualToConstant:44],
    [keyboard.heightAnchor constraintEqualToConstant:44],
  ]];

  UIPanGestureRecognizer* move =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleMove:)];
  move.minimumNumberOfTouches = 1;
  move.maximumNumberOfTouches = 1;
  [self addGestureRecognizer:move];

  UIPanGestureRecognizer* scroll =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleScroll:)];
  scroll.minimumNumberOfTouches = 2;
  scroll.maximumNumberOfTouches = 2;
  [self addGestureRecognizer:scroll];

  UITapGestureRecognizer* tap =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleTap:)];
  [self addGestureRecognizer:tap];

  UITapGestureRecognizer* rightTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleRightTap:)];
  rightTap.numberOfTouchesRequired = 2;
  [self addGestureRecognizer:rightTap];

  // Phone-side pointer fallback (mouse driving the iOS pointer).
  tap.delegate = self;
  rightTap.delegate = self;
  move.delegate = self;
  scroll.delegate = self;
  UITapGestureRecognizer* secondaryClick = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleRightTap:)];
  secondaryClick.buttonMaskRequired = UIEventButtonMaskSecondary;
  secondaryClick.allowedTouchTypes = @[ @(UITouchTypeIndirectPointer) ];
  secondaryClick.delegate = self;
  [self addGestureRecognizer:secondaryClick];
  UIPanGestureRecognizer* wheel =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleWheel:)];
  wheel.allowedScrollTypesMask = UIScrollTypeMaskAll;
  wheel.maximumNumberOfTouches = 0;
  wheel.delegate = self;
  [self addGestureRecognizer:wheel];
  UIHoverGestureRecognizer* hover =
      [[UIHoverGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handleHover:)];
  hover.delegate = self;
  [self addGestureRecognizer:hover];
  // Keep the iOS pointer invisible over the trackpad: the cursor that matters
  // is the one drawn on the monitor.
  [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];

  _mice = [NSMutableSet set];

  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  for (NSNotificationName name in @[
         UISceneWillConnectNotification, UISceneDidActivateNotification,
         UISceneDidDisconnectNotification
       ]) {
    [center addObserver:self
               selector:@selector(scenesChanged:)
                   name:name
                 object:nil];
  }
  [center addObserver:self
             selector:@selector(mouseConnected:)
                 name:GCMouseDidConnectNotification
               object:nil];
  [center addObserver:self
             selector:@selector(mouseDisconnected:)
                 name:GCMouseDidDisconnectNotification
               object:nil];
  for (GCMouse* mouse in GCMouse.mice) {
    [self attachMouse:mouse];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  [self refreshExternalState];
}

- (void)scenesChanged:(NSNotification*)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self refreshExternalState];
  });
}

- (void)refreshExternalState {
  UIWindowScene* scene = ExternalScene();
  BOOL external = scene != nil;
  // Without a monitor the phone says what to do instead of going black; the
  // desktop window only ever lives on the external display.
  _hint.text = external ? kTrackpadHint : kConnectDisplayHint;
  _keyboardButton.hidden = !external;
  self.userInteractionEnabled = external;
  if (!external) {
    if (self.isFirstResponder) {
      [self resignFirstResponder];
    }
    _cursorWindow.hidden = YES;
    _cursorWindow = nil;
    _cursorPlaced = NO;
    return;
  }
  if (_cursorWindow.windowScene != scene) {
    _cursorWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _cursorWindow.frame = scene.screen.bounds;
    _cursorWindow.windowLevel = UIWindowLevelAlert + 100;
    _cursorWindow.userInteractionEnabled = NO;
    _cursorWindow.backgroundColor = UIColor.clearColor;
    _cursorWindow.rootViewController = [[UIViewController alloc] init];
    _cursorWindow.rootViewController.view.backgroundColor =
        UIColor.clearColor;
    _cursorWindow.rootViewController.view.userInteractionEnabled = NO;
    _cursorLayer = [CAShapeLayer layer];
    UIBezierPath* arrow = [UIBezierPath bezierPath];
    [arrow moveToPoint:CGPointMake(0, 0)];
    [arrow addLineToPoint:CGPointMake(0, 17)];
    [arrow addLineToPoint:CGPointMake(4.5, 13)];
    [arrow addLineToPoint:CGPointMake(7.5, 19.5)];
    [arrow addLineToPoint:CGPointMake(10, 18.5)];
    [arrow addLineToPoint:CGPointMake(7, 12)];
    [arrow addLineToPoint:CGPointMake(12.5, 12)];
    [arrow closePath];
    _cursorLayer.path = arrow.CGPath;
    _cursorLayer.fillColor = UIColor.blackColor.CGColor;
    _cursorLayer.strokeColor = UIColor.whiteColor.CGColor;
    _cursorLayer.lineWidth = 1.2;
    _cursorLayer.bounds = CGRectMake(0, 0, 13, 20);
    _cursorLayer.anchorPoint = CGPointZero;
    [_cursorWindow.rootViewController.view.layer addSublayer:_cursorLayer];
    _cursorWindow.hidden = NO;
    if (!_cursorPlaced) {
      _cursor = CGPointMake(CGRectGetMidX(scene.screen.bounds),
                            CGRectGetMidY(scene.screen.bounds));
      _cursorPlaced = YES;
    }
    [self placeCursor];
    NSLog(@"[DeskBrowser] trackpad attached external=%@",
          NSStringFromCGRect(scene.screen.bounds));
  }
  if (!self.isFirstResponder && self.window) {
    [self becomeFirstResponder];
  }
}

- (void)placeCursor {
  display::UpdateCursorScreenPointForIOS(gfx::Point(_cursor.x, _cursor.y));
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _cursorLayer.position = _cursor;
  [CATransaction commit];
}

#pragma mark - Hit testing and dispatch

// Front-most widget window under the cursor, and the UIView hit inside it.
- (UIWindow*)widgetWindowAtCursor:(UIView**)hitView {
  // A menu must get clicks even outside its bounds (to cancel itself), and
  // drags must keep targeting their capture widget instead of the page below.
  UIWindow* capture = views::NativeWidgetIOS::GetCaptureWindow().Get();
  if (capture && !capture.hidden && capture.windowScene == ExternalScene()) {
    if (hitView) {
      *hitView = capture.rootViewController.view;
    }
    return capture;
  }
  UIWindowScene* scene = ExternalScene();
  if (!scene) {
    return nil;
  }
  for (UIWindow* window in WidgetWindowsFrontToBack(scene)) {
    CGPoint p = [window convertPoint:_cursor
                 fromCoordinateSpace:scene.screen.coordinateSpace];
    if (![window pointInside:p withEvent:nil]) {
      continue;
    }
    UIView* hit = [window hitTest:p withEvent:nil];
    UIView* hit_web = hit;
    while (hit_web && !IsWebInputView(hit_web)) {
      hit_web = hit_web.superview;
    }
    if (hit_web && !AcceptsWebInput(hit_web)) {
      hit = FindAcceptingWebView(window, p);
    }
    if (hitView) {
      *hitView = hit;
    }
    return window;
  }
  return nil;
}

- (void)sendViewsMouse:(ui::EventType)type
              toWindow:(UIWindow*)window
                 flags:(int)flags
               changed:(int)changed
                clicks:(int)clicks {
  CGPoint p = [window convertPoint:_cursor
               fromCoordinateSpace:window.screen.coordinateSpace];
  gfx::PointF location(p.x, p.y);
  ui::MouseEvent event(type, location, location, base::TimeTicks::Now(),
                       flags, changed);
  if (clicks) {
    event.SetClickCount(clicks);
  }
  views::NativeWidgetIOS::DispatchTrackpadMouseEvent(
      gfx::NativeWindow(window), &event);
}

- (CGPoint)cursorInView:(UIView*)view {
  return [view convertPoint:_cursor
        fromCoordinateSpace:view.window.screen.coordinateSpace];
}

- (void)moveCursorBy:(CGPoint)delta {
  UIWindowScene* scene = ExternalScene();
  if (!scene) {
    return;
  }
  CGRect bounds = scene.screen.bounds;
  _cursor.x = std::clamp(_cursor.x + delta.x * kCursorGain,
                         CGRectGetMinX(bounds), CGRectGetMaxX(bounds) - 1);
  _cursor.y = std::clamp(_cursor.y + delta.y * kCursorGain,
                         CGRectGetMinY(bounds), CGRectGetMaxY(bounds) - 1);
  [self placeCursor];

  UIView* hit = nil;
  UIWindow* window = [self widgetWindowAtCursor:&hit];
  if (_hoverWindow && _hoverWindow != window) {
    [self sendViewsMouse:ui::EventType::kMouseExited
                toWindow:_hoverWindow
                   flags:0
                 changed:0
                  clicks:0];
  }
  _hoverWindow = window;
  if (!window) {
    return;
  }
  if (id<ChromeViewsIOSWebInput> web = WebInputForView(hit)) {
    [web deskBrowserInjectMouseAtViewPoint:[self cursorInView:(UIView*)web]
                                      type:0
                                    button:0];
    return;
  }
  [self sendViewsMouse:ui::EventType::kMouseMoved
              toWindow:window
                 flags:0
               changed:0
                clicks:0];
}

- (void)clickWithButton:(int)button {
  UIView* hit = nil;
  UIWindow* window = [self widgetWindowAtCursor:&hit];
  if (!window) {
    return;
  }
  id<ChromeViewsIOSWebInput> web = WebInputForView(hit);
  NSLog(@"[DeskBrowser] trackpad click at %@ button=%d target=%@",
        NSStringFromCGPoint(_cursor), button, web ? @"web" : @"views");
  const NSInteger web_button = button == ui::EF_LEFT_MOUSE_BUTTON     ? 1
                               : button == ui::EF_RIGHT_MOUSE_BUTTON  ? 2
                               : button == ui::EF_MIDDLE_MOUSE_BUTTON ? 3
                                                                      : 0;
  if (web && web_button) {
    CGPoint p = [self cursorInView:(UIView*)web];
    [web deskBrowserInjectMouseAtViewPoint:p type:0 button:0];
    [web deskBrowserInjectMouseAtViewPoint:p type:1 button:web_button];
    [web deskBrowserInjectMouseAtViewPoint:p type:2 button:web_button];
    _keyWebView = (UIView*)web;
    _keyWidgetWindow = window;
    return;
  }
  [self sendViewsMouse:ui::EventType::kMouseMoved
              toWindow:window
                 flags:0
               changed:0
                clicks:0];
  [self sendViewsMouse:ui::EventType::kMousePressed
              toWindow:window
                 flags:button
               changed:button
                clicks:1];
  [self sendViewsMouse:ui::EventType::kMouseReleased
              toWindow:window
                 flags:button
               changed:button
                clicks:1];
  if (!web) {
    _keyWebView = nil;
  }
  _keyWidgetWindow = window;
}

#pragma mark - Gestures

- (void)handleMove:(UIPanGestureRecognizer*)pan {
  CGPoint t = [pan translationInView:self];
  if (pan.state == UIGestureRecognizerStateBegan) {
    _lastPan = CGPointZero;
  }
  [self moveCursorBy:CGPointMake(t.x - _lastPan.x, t.y - _lastPan.y)];
  _lastPan = t;
  if (pan.state == UIGestureRecognizerStateEnded) {
    NSLog(@"[DeskBrowser] trackpad cursor=%@", NSStringFromCGPoint(_cursor));
  }
}

- (void)handleTap:(UITapGestureRecognizer*)tap {
  if (tap.state == UIGestureRecognizerStateRecognized) {
    [self clickWithButton:ui::EF_LEFT_MOUSE_BUTTON];
  }
}

- (void)handleRightTap:(UITapGestureRecognizer*)tap {
  if (tap.state == UIGestureRecognizerStateRecognized) {
    [self clickWithButton:ui::EF_RIGHT_MOUSE_BUTTON];
  }
}

- (void)handleScroll:(UIPanGestureRecognizer*)pan {
  CGPoint t = [pan translationInView:self];
  if (pan.state == UIGestureRecognizerStateBegan) {
    _lastScroll = CGPointZero;
  }
  CGPoint delta = CGPointMake((t.x - _lastScroll.x) * kScrollGain,
                              (t.y - _lastScroll.y) * kScrollGain);
  _lastScroll = t;
  UIView* hit = nil;
  UIWindow* window = [self widgetWindowAtCursor:&hit];
  if (!window) {
    return;
  }
  NSInteger phase = pan.state == UIGestureRecognizerStateBegan ? 0
                    : (pan.state == UIGestureRecognizerStateEnded ||
                       pan.state == UIGestureRecognizerStateCancelled)
                        ? 2
                        : 1;
  if (id<ChromeViewsIOSWebInput> web = WebInputForView(hit)) {
    [web deskBrowserInjectWheelAtViewPoint:[self cursorInView:(UIView*)web]
                                     delta:delta
                                     phase:phase];
    return;
  }
  CGPoint p = [window convertPoint:_cursor
               fromCoordinateSpace:window.screen.coordinateSpace];
  gfx::Point location(p.x, p.y);
  ui::MouseWheelEvent wheel(gfx::Vector2d(delta.x, delta.y), location,
                            location, base::TimeTicks::Now(), 0, 0);
  views::NativeWidgetIOS::DispatchTrackpadMouseEvent(
      gfx::NativeWindow(window), &wheel);
}

#pragma mark - Hardware mouse

- (BOOL)gcMouseActive {
  return _mice.count > 0 && CACurrentMediaTime() - _gcMouseLastEvent < 1.0;
}

- (void)mouseConnected:(NSNotification*)notification {
  [self attachMouse:notification.object];
}

- (void)mouseDisconnected:(NSNotification*)notification {
  GCMouse* mouse = notification.object;
  [_mice removeObject:mouse];
  if (_mice.count == 0 && _mouseButtons) {
    // Release anything still held so drags do not stick.
    for (int b : {ui::EF_LEFT_MOUSE_BUTTON, ui::EF_RIGHT_MOUSE_BUTTON,
                  ui::EF_MIDDLE_MOUSE_BUTTON}) {
      if (_mouseButtons & b) {
        [self mouseButton:b pressed:NO];
      }
    }
  }
}

- (void)attachMouse:(GCMouse*)mouse {
  if (!mouse || [_mice containsObject:mouse]) {
    return;
  }
  [_mice addObject:mouse];
  NSLog(@"[DeskBrowser] mouse connected %@", mouse.vendorName);
  __weak ChromeViewsIOSTrackpadView* weakSelf = self;
  GCMouseInput* input = mouse.mouseInput;
  // GameController reports +y as up; screen +y is down.
  input.mouseMovedHandler = ^(GCMouseInput* m, float dx, float dy) {
    dispatch_async(dispatch_get_main_queue(), ^{
      ChromeViewsIOSTrackpadView* strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf->_gcMouseLastEvent = CACurrentMediaTime();
      [strongSelf movePointerBy:CGPointMake(dx * kMouseGain, -dy * kMouseGain)];
    });
  };
  auto button_handler =
      [weakSelf](int button) -> GCControllerButtonValueChangedHandler {
    return ^(GCControllerButtonInput* b, float value, BOOL pressed) {
      dispatch_async(dispatch_get_main_queue(), ^{
        ChromeViewsIOSTrackpadView* strongSelf = weakSelf;
        if (!strongSelf) {
          return;
        }
        strongSelf->_gcMouseLastEvent = CACurrentMediaTime();
        [strongSelf mouseButton:button pressed:pressed];
      });
    };
  };
  input.leftButton.pressedChangedHandler =
      button_handler(ui::EF_LEFT_MOUSE_BUTTON);
  input.rightButton.pressedChangedHandler =
      button_handler(ui::EF_RIGHT_MOUSE_BUTTON);
  input.middleButton.pressedChangedHandler =
      button_handler(ui::EF_MIDDLE_MOUSE_BUTTON);
  input.scroll.valueChangedHandler =
      ^(GCControllerDirectionPad* pad, float x, float y) {
        if (x == 0 && y == 0) {
          return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          ChromeViewsIOSTrackpadView* strongSelf = weakSelf;
          if (!strongSelf) {
            return;
          }
          strongSelf->_gcMouseLastEvent = CACurrentMediaTime();
          // Wheel up (+y) scrolls the page up: Chrome deltas are positive up.
          [strongSelf wheelBy:CGPointMake(-x * kWheelNotch, y * kWheelNotch)
                        phase:1];
        });
      };
}

// Relative pointer motion in external screen points (no trackpad gain).
- (void)movePointerBy:(CGPoint)delta {
  if (_mouseButtons) {
    [self dragCursorBy:delta];
    return;
  }
  [self moveCursorBy:CGPointMake(delta.x / kCursorGain, delta.y / kCursorGain)];
}

- (void)dragCursorBy:(CGPoint)delta {
  UIWindowScene* scene = ExternalScene();
  if (!scene) {
    return;
  }
  CGRect bounds = scene.screen.bounds;
  _cursor.x = std::clamp(_cursor.x + delta.x, CGRectGetMinX(bounds),
                         CGRectGetMaxX(bounds) - 1);
  _cursor.y = std::clamp(_cursor.y + delta.y, CGRectGetMinY(bounds),
                         CGRectGetMaxY(bounds) - 1);
  [self placeCursor];
  // Drags stay with the target that got the press, as on desktop.
  if (UIView* web = _pressWebView) {
    const NSInteger web_button =
        (_mouseButtons & ui::EF_LEFT_MOUSE_BUTTON)    ? 1
        : (_mouseButtons & ui::EF_RIGHT_MOUSE_BUTTON) ? 2
                                                      : 3;
    [(id<ChromeViewsIOSWebInput>)web
        deskBrowserInjectMouseAtViewPoint:[self cursorInView:web]
                                     type:0
                                   button:web_button];
    return;
  }
  if (UIWindow* window = _pressWindow) {
    [self sendViewsMouse:ui::EventType::kMouseDragged
                toWindow:window
                   flags:_mouseButtons
                 changed:0
                  clicks:0];
  }
}

- (void)mouseButton:(int)button pressed:(BOOL)pressed {
  if (pressed == !!(_mouseButtons & button)) {
    return;
  }
  if (pressed) {
    const CFTimeInterval now = CACurrentMediaTime();
    if (button == _lastClickButton &&
        now - _lastClickTime < kMultiClickSeconds &&
        std::abs(_cursor.x - _lastClickPoint.x) <= kMultiClickSlop &&
        std::abs(_cursor.y - _lastClickPoint.y) <= kMultiClickSlop) {
      _clickCount = std::min(_clickCount + 1, 3);
    } else {
      _clickCount = 1;
    }
    _lastClickTime = now;
    _lastClickPoint = _cursor;
    _lastClickButton = button;

    _mouseButtons |= button;
    UIView* hit = nil;
    UIWindow* window = [self widgetWindowAtCursor:&hit];
    _pressWindow = window;
    _pressWebView = nil;
    if (!window) {
      return;
    }
    id<ChromeViewsIOSWebInput> web = WebInputForView(hit);
    const NSInteger web_button = button == ui::EF_LEFT_MOUSE_BUTTON    ? 1
                                 : button == ui::EF_RIGHT_MOUSE_BUTTON ? 2
                                                                       : 3;
    if (web) {
      _pressWebView = (UIView*)web;
      CGPoint p = [self cursorInView:(UIView*)web];
      [web deskBrowserInjectMouseAtViewPoint:p type:0 button:0];
      [web deskBrowserInjectMouseAtViewPoint:p type:1 button:web_button];
      _keyWebView = (UIView*)web;
      _keyWidgetWindow = window;
      return;
    }
    _keyWebView = nil;
    _keyWidgetWindow = window;
    [self sendViewsMouse:ui::EventType::kMouseMoved
                toWindow:window
                   flags:0
                 changed:0
                  clicks:0];
    [self sendViewsMouse:ui::EventType::kMousePressed
                toWindow:window
                   flags:_mouseButtons
                 changed:button
                  clicks:_clickCount];
    return;
  }
  const int flags = _mouseButtons;
  _mouseButtons &= ~button;
  if (UIView* web = _pressWebView) {
    const NSInteger web_button = button == ui::EF_LEFT_MOUSE_BUTTON    ? 1
                                 : button == ui::EF_RIGHT_MOUSE_BUTTON ? 2
                                                                       : 3;
    [(id<ChromeViewsIOSWebInput>)web
        deskBrowserInjectMouseAtViewPoint:[self cursorInView:web]
                                     type:2
                                   button:web_button];
  } else if (UIWindow* window = _pressWindow) {
    [self sendViewsMouse:ui::EventType::kMouseReleased
                toWindow:window
                   flags:flags
                 changed:button
                  clicks:_clickCount];
  }
  if (!_mouseButtons) {
    _pressWebView = nil;
    _pressWindow = nil;
  }
}

- (void)wheelBy:(CGPoint)delta phase:(NSInteger)phase {
  UIView* hit = nil;
  UIWindow* window = [self widgetWindowAtCursor:&hit];
  if (!window) {
    return;
  }
  if (id<ChromeViewsIOSWebInput> web = WebInputForView(hit)) {
    [web deskBrowserInjectWheelAtViewPoint:[self cursorInView:(UIView*)web]
                                     delta:delta
                                     phase:phase];
    return;
  }
  CGPoint p = [window convertPoint:_cursor
               fromCoordinateSpace:window.screen.coordinateSpace];
  gfx::Point location(p.x, p.y);
  ui::MouseWheelEvent wheel(gfx::Vector2d(delta.x, delta.y), location,
                            location, base::TimeTicks::Now(), 0, 0);
  views::NativeWidgetIOS::DispatchTrackpadMouseEvent(
      gfx::NativeWindow(window), &wheel);
}

// Phone-side pointer fallback: the iOS pointer's motion over the trackpad
// drives the monitor cursor 1:1 in phone points times the trackpad gain.
- (void)handleHover:(UIHoverGestureRecognizer*)hover {
  if ([self gcMouseActive]) {
    _hoverValid = NO;
    return;
  }
  CGPoint p = [hover locationInView:self];
  switch (hover.state) {
    case UIGestureRecognizerStateBegan:
      _lastHover = p;
      _hoverValid = YES;
      break;
    case UIGestureRecognizerStateChanged:
      if (_hoverValid) {
        [self moveCursorBy:CGPointMake(p.x - _lastHover.x, p.y - _lastHover.y)];
      }
      _lastHover = p;
      _hoverValid = YES;
      break;
    default:
      _hoverValid = NO;
      break;
  }
}

// Mouse wheel / trackpad scroll arriving as UIKit scroll events (no touches).
- (void)handleWheel:(UIPanGestureRecognizer*)pan {
  if ([self gcMouseActive]) {
    return;
  }
  [self handleScroll:pan];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)recognizer
       shouldReceiveTouch:(UITouch*)touch {
  // While GameController owns the mouse, its clicks arrive there; drop the
  // duplicate indirect-pointer touches UIKit also delivers.
  if (touch.type == UITouchTypeIndirectPointer && [self gcMouseActive]) {
    return NO;
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)recognizer
    shouldReceiveEvent:(UIEvent*)event {
  if (event.type == UIEventTypeScroll && [self gcMouseActive]) {
    return NO;
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)a
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer*)b {
  return [a isKindOfClass:UIHoverGestureRecognizer.class] ||
         [b isKindOfClass:UIHoverGestureRecognizer.class];
}

- (UIPointerStyle*)pointerInteraction:(UIPointerInteraction*)interaction
                       styleForRegion:(UIPointerRegion*)region {
  return [UIPointerStyle hiddenPointerStyle];
}

#pragma mark - Keyboard

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (UIView*)inputView {
  return _softKeyboard ? nil : _emptyInputView;
}

- (void)toggleKeyboard {
  _softKeyboard = !_softKeyboard;
  if (!self.isFirstResponder) {
    [self becomeFirstResponder];
  }
  [self reloadInputViews];
}

- (UIWindow*)keyWindowForViews {
  if (_keyWidgetWindow && !_keyWidgetWindow.hidden) {
    return _keyWidgetWindow;
  }
  UIWindowScene* scene = ExternalScene();
  return scene ? WidgetWindowsFrontToBack(scene).firstObject : nil;
}

- (void)sendKey:(ui::KeyboardCode)code key:(ui::DomKey)key flags:(int)flags {
  UIWindow* window = [self keyWindowForViews];
  if (!window) {
    return;
  }
  ui::KeyEvent press(ui::EventType::kKeyPressed, code, ui::DomCode::NONE,
                     flags, key, base::TimeTicks::Now());
  views::NativeWidgetIOS::DispatchTrackpadKeyEvent(gfx::NativeWindow(window),
                                                   &press);
  ui::KeyEvent release(ui::EventType::kKeyReleased, code, ui::DomCode::NONE,
                       flags, key, base::TimeTicks::Now());
  views::NativeWidgetIOS::DispatchTrackpadKeyEvent(gfx::NativeWindow(window),
                                                   &release);
}

- (BOOL)hasText {
  return YES;
}

- (void)insertText:(NSString*)text {
  if (id<ChromeViewsIOSWebInput> web =
          static_cast<id<ChromeViewsIOSWebInput>>(
              views::NativeWidgetIOS::HasKeyEventMonitor() ? nil : _keyWebView)) {
    [self insertText:text intoWeb:web];
    return;
  }
  for (NSUInteger i = 0; i < text.length; ++i) {
    unichar c = [text characterAtIndex:i];
    if (c == '\n' || c == '\r') {
      [self sendKey:ui::VKEY_RETURN key:ui::DomKey::ENTER flags:0];
    } else if (c == '\t') {
      [self sendKey:ui::VKEY_TAB key:ui::DomKey::TAB flags:0];
    } else {
      int flags = (c >= 'A' && c <= 'Z') ? ui::EF_SHIFT_DOWN : 0;
      [self sendKey:KeyCodeForCharacter(c)
                key:ui::DomKey::FromCharacter(c)
              flags:flags];
    }
  }
}

// Typed text goes to the page as text, but Return and Tab (the on-screen
// keyboard's return key, or a hardware key that reached UIKeyInput) become
// real key events so pages get keydown Enter and can submit or preventDefault.
- (void)insertText:(NSString*)text intoWeb:(id<ChromeViewsIOSWebInput>)web {
  const BOOL can_key = [web respondsToSelector:@selector(deskBrowserInjectKeyWithWindowsKeyCode:domCode:domKey:text:modifiers:)];
  if (!can_key) {
    [web insertText:text];
    return;
  }
  NSMutableString* run = [NSMutableString string];
  for (NSUInteger i = 0; i < text.length; ++i) {
    unichar c = [text characterAtIndex:i];
    KeyMapping key;
    bool special = false;
    if (c == '\n' || c == '\r') {
      special = WebKeyForHIDUsage(UIKeyboardHIDUsageKeyboardReturnOrEnter, &key);
      if (c == '\r' && i + 1 < text.length &&
          [text characterAtIndex:i + 1] == '\n') {
        ++i;  // CRLF is one Enter.
      }
    } else if (c == '\t') {
      special = WebKeyForHIDUsage(UIKeyboardHIDUsageKeyboardTab, &key);
    }
    if (!special) {
      [run appendFormat:@"%C", c];
      continue;
    }
    if (run.length) {
      [web insertText:[run copy]];
      [run setString:@""];
    }
    [self sendWebKey:key flags:0 to:web];
  }
  if (run.length) {
    [web insertText:[run copy]];
  }
}

- (void)sendWebKey:(const KeyMapping&)key
             flags:(int)flags
                to:(id<ChromeViewsIOSWebInput>)web {
  NSLog(@"[DeskBrowser] trackpad webKey code=%d", static_cast<int>(key.code));
  [web deskBrowserInjectKeyWithWindowsKeyCode:key.code
                                      domCode:static_cast<NSInteger>(
                                                  key.dom_code)
                                       domKey:static_cast<NSInteger>(
                                                  static_cast<ui::DomKey::Base>(
                                                      key.dom_key))
                                         text:key.text
                                    modifiers:WebModifiersForUIFlags(flags)];
}

- (void)deleteBackward {
  if (id<ChromeViewsIOSWebInput> web =
          static_cast<id<ChromeViewsIOSWebInput>>(
              views::NativeWidgetIOS::HasKeyEventMonitor() ? nil : _keyWebView)) {
    [web deleteBackward];
    return;
  }
  [self sendKey:ui::VKEY_BACK key:ui::DomKey::BACKSPACE flags:0];
}

// Keys that never reach UIKeyInput: arrows, Escape, and Command shortcuts.
- (void)pressesBegan:(NSSet<UIPress*>*)presses
           withEvent:(UIPressesEvent*)event {
  NSMutableSet<UIPress*>* unhandled = [NSMutableSet set];
  for (UIPress* press in presses) {
    UIKey* key = press.key;
    if (!key) {
      [unhandled addObject:press];
      continue;
    }
    int flags = 0;
    if (key.modifierFlags & UIKeyModifierCommand) {
      flags |= ui::EF_COMMAND_DOWN;
    }
    if (key.modifierFlags & UIKeyModifierShift) {
      flags |= ui::EF_SHIFT_DOWN;
    }
    if (key.modifierFlags & UIKeyModifierAlternate) {
      flags |= ui::EF_ALT_DOWN;
    }
    if (key.modifierFlags & UIKeyModifierControl) {
      flags |= ui::EF_CONTROL_DOWN;
    }
    // Page keys (Enter, Tab, Escape, arrows, paging) go to the clicked web
    // view as real key events. Without this, Return reached the page only as
    // typed "\n" (a newline in Google's search box, no search), and arrows
    // and Escape never reached it at all.
    {
      KeyMapping web_key;
      id<ChromeViewsIOSWebInput> web =
          static_cast<id<ChromeViewsIOSWebInput>>(_keyWebView);
      if (web && !(flags & ui::EF_COMMAND_DOWN) &&
          !views::NativeWidgetIOS::HasKeyEventMonitor() &&
          WebKeyForHIDUsage(key.keyCode, &web_key) &&
          [web respondsToSelector:@selector(deskBrowserInjectKeyWithWindowsKeyCode:domCode:domKey:text:modifiers:)]) {
        [self sendWebKey:web_key flags:flags to:web];
        continue;
      }
    }
    ui::KeyboardCode code = ui::VKEY_UNKNOWN;
    ui::DomKey dom = ui::DomKey::NONE;
    switch (key.keyCode) {
      case UIKeyboardHIDUsageKeyboardLeftArrow:
        code = ui::VKEY_LEFT;
        dom = ui::DomKey::ARROW_LEFT;
        break;
      case UIKeyboardHIDUsageKeyboardRightArrow:
        code = ui::VKEY_RIGHT;
        dom = ui::DomKey::ARROW_RIGHT;
        break;
      case UIKeyboardHIDUsageKeyboardUpArrow:
        code = ui::VKEY_UP;
        dom = ui::DomKey::ARROW_UP;
        break;
      case UIKeyboardHIDUsageKeyboardDownArrow:
        code = ui::VKEY_DOWN;
        dom = ui::DomKey::ARROW_DOWN;
        break;
      case UIKeyboardHIDUsageKeyboardEscape:
        code = ui::VKEY_ESCAPE;
        dom = ui::DomKey::ESCAPE;
        break;
      default:
        if (flags & ui::EF_COMMAND_DOWN) {
          NSString* chars = key.charactersIgnoringModifiers.lowercaseString;
          if (chars.length == 1) {
            unichar c = [chars characterAtIndex:0];
            code = KeyCodeForCharacter(c);
            dom = ui::DomKey::FromCharacter(c);
          }
        }
        break;
    }
    // Browser shortcuts win over the page, as on desktop.
    const bool shortcut = flags & ui::EF_COMMAND_DOWN;
    if (code == ui::VKEY_UNKNOWN ||
        (_keyWebView && !shortcut &&
         !views::NativeWidgetIOS::HasKeyEventMonitor())) {
      [unhandled addObject:press];
      continue;
    }
    if (shortcut) {
      _keyWebView = nil;
    }
    [self sendKey:code key:dom flags:flags];
  }
  if (unhandled.count) {
    [super pressesBegan:unhandled withEvent:event];
  }
}

@end
