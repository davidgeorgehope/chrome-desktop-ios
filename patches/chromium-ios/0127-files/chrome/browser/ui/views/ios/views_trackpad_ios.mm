// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/views/ios/views_trackpad_ios.h"

#include <algorithm>

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
@end

namespace {

constexpr CGFloat kCursorGain = 2.5;  // Phone points to external points.
constexpr CGFloat kScrollGain = 3.0;

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
  // Hardware keys need first responder; an empty input view keeps the
  // on-screen keyboard down until the keyboard button asks for it.
  UIView* _emptyInputView;
  BOOL _softKeyboard;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) {
    return nil;
  }
  self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
  self.multipleTouchEnabled = YES;
  self.hidden = YES;
  _emptyInputView = [[UIView alloc] initWithFrame:CGRectZero];

  _hint = [[UILabel alloc] init];
  _hint.text = @"Trackpad\nOne finger: move · Tap: click\nTwo fingers: "
               @"scroll · Two-finger tap: right-click";
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
  self.hidden = !external;
  if (!external) {
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     [ChromeViewsIOSTrackpadView auditWindows];
                   });
  }
  if (!self.isFirstResponder && self.window) {
    [self becomeFirstResponder];
  }
}

// Diagnostics: which windows live on which scene (stray-widget check).
+ (void)auditWindows {
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    UIWindowScene* ws = (UIWindowScene*)scene;
    if (![ws isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    for (UIWindow* w in ws.windows) {
      NSLog(@"[DeskBrowser] audit scene=%@ window=%@ level=%.0f hidden=%d "
            @"frame=%@ root=%@",
            ws.session.role, NSStringFromClass([w class]), w.windowLevel,
            w.hidden, NSStringFromCGRect(w.frame),
            NSStringFromClass([w.rootViewController.view class]));
    }
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
  if (pan.state != UIGestureRecognizerStateChanged) {
    NSLog(@"[DeskBrowser] trackpad scroll state=%ld delta=%@ hit=%@",
          (long)pan.state, NSStringFromCGPoint(delta),
          NSStringFromClass([hit class]));
  }
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

#pragma mark - Keyboard

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  BOOL became = [super becomeFirstResponder];
  NSLog(@"[DeskBrowser] trackpad becomeFirstResponder=%d", became);
  return became;
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
  NSLog(@"[DeskBrowser] trackpad insertText len=%lu web=%d",
        (unsigned long)text.length, _keyWebView != nil);
  if (id<ChromeViewsIOSWebInput> web =
          static_cast<id<ChromeViewsIOSWebInput>>(_keyWebView)) {
    [web insertText:text];
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

- (void)deleteBackward {
  if (id<ChromeViewsIOSWebInput> web =
          static_cast<id<ChromeViewsIOSWebInput>>(_keyWebView)) {
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
    if (code == ui::VKEY_UNKNOWN || (_keyWebView && !shortcut)) {
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
