// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/views/ios/views_trackpad_ios.h"

#import <GameController/GameController.h>

#include <algorithm>
#include <cmath>

#include "base/time/time.h"
#include "chrome/browser/ui/views/ios/views_trackpad_ios_geometry.h"
#include "ui/display/ios/phone_desktop_ios.h"
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
#include "ui/views/controls/textfield/textfield.h"
#include "ui/views/focus/focus_manager.h"
#include "ui/views/view.h"
#include "ui/views/view_utils.h"
#include "ui/views/widget/native_widget_ios.h"
#include "ui/views/widget/widget.h"

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
// Whether the focused element takes text (an input, textarea, editable).
- (BOOL)deskBrowserIsEditable;
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
// On-phone desktop: a one-finger fling keeps scrolling, slowing by this
// factor every 1/60 s, until it drops under kFlingStopSpeed (panel pt/s).
constexpr CGFloat kFlingDecayPerFrame = 0.95;
constexpr CGFloat kFlingStopSpeed = 30.0;
// Text input state reaches the web view after the click round-trips through
// the renderer.
constexpr double kKeyboardCheckDelaySeconds = 0.35;

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
NSString* const kRotateHint =
    @"Chrome Desktop\nTurn your iPhone to landscape\n(top of the phone to the "
    @"left).";
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

// The external display in desktop DIPs (its UIKit points; display::ScreenIos
// uses the same rect for the primary display that the browser window fills).
CGRect DesktopBounds(UIWindowScene* scene) {
  return scene ? scene.screen.bounds : CGRectZero;
}

views_trackpad_ios::Extent ExtentOf(CGRect r) {
  return {r.origin.x, r.origin.y, r.size.width, r.size.height};
}

bool SameExtent(views_trackpad_ios::Extent a, views_trackpad_ios::Extent b) {
  return a.x == b.x && a.y == b.y && a.width == b.width &&
         a.height == b.height;
}

bool PanelMayRotate() {
  const CGSize native = UIScreen.mainScreen.nativeBounds.size;
  return views_trackpad_ios::PanelMayRotate(native.width, native.height);
}

}  // namespace

UIInterfaceOrientationMask ChromeViewsIOSPhoneOrientations(void) {
  // External-display mode keeps the app's usual orientations. The on-phone
  // desktop holds a tall phone in landscape-right; a squarer panel (iPhone
  // Duo class) follows the device.
  if (display::GetPhoneDesktopForIOS().active && !PanelMayRotate()) {
    return UIInterfaceOrientationMaskLandscapeRight;
  }
  return UIInterfaceOrientationMaskAllButUpsideDown;
}

// Root of the cursor's window. It is the topmost full-screen window, so iOS
// asks it about orientation and the status bar: it must answer like the
// phone host, or the scene rotates to portrait and the status bar is drawn
// over the desktop.
@interface ChromeViewsIOSCursorWindowController : UIViewController
@end

@implementation ChromeViewsIOSCursorWindowController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return ChromeViewsIOSPhoneOrientations();
}
- (BOOL)prefersStatusBarHidden {
  return display::GetPhoneDesktopForIOS().active;
}
- (BOOL)prefersHomeIndicatorAutoHidden {
  return YES;
}
@end

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
  // Set once a connected GCMouse has reported motion. From then on the iOS
  // pointer (absolute, phone-bounded) is ignored entirely so the two paths
  // never fight over the cursor.
  BOOL _gcMouseDelivering;
  BOOL _loggedPointerFallback;
  // The one-finger pan, and whether its touch is the iOS pointer (a mouse
  // drag in the fallback path) rather than a finger.
  __weak UIPanGestureRecognizer* _movePan;
  BOOL _movePanIsPointer;
  int _mouseButtons;  // ui::EF_*_MOUSE_BUTTON flags held down.
  __weak UIView* _pressWebView;
  __weak UIWindow* _pressWindow;
  CFTimeInterval _lastClickTime;
  CGPoint _lastClickPoint;
  int _lastClickButton;
  int _clickCount;
  CGPoint _lastHover;
  BOOL _hoverValid;
  // On-phone desktop (no external display): the desktop is laid out at
  // |_desktop| DIPs and drawn on this panel through |_viewport|; touches act
  // where they land. |_usable| is the panel minus the side safe areas.
  BOOL _phoneMode;
  views_trackpad_ios::Extent _desktop;
  views_trackpad_ios::Extent _usable;
  views_trackpad_ios::Viewport _viewport;
  // The cursor is drawn on the panel only once a mouse has moved it.
  BOOL _pointerSeen;
  BOOL _longPressFired;
  CGFloat _lastPinchScale;
  CGPoint _lastViewportPan;
  __weak UIPanGestureRecognizer* _scrollPan;
  __weak UIPinchGestureRecognizer* _pinch;
  __weak UILongPressGestureRecognizer* _longPress;
  // A tall phone that iOS shows in portrait anyway: the desktop stays laid
  // out for landscape-right and a "turn to landscape" screen covers it.
  BOOL _rotateHint;
  CADisplayLink* _fling;
  CGPoint _flingVelocity;
  CFTimeInterval _flingLast;
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
  _movePan = move;

  UIPanGestureRecognizer* scroll =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleScroll:)];
  scroll.minimumNumberOfTouches = 2;
  scroll.maximumNumberOfTouches = 2;
  [self addGestureRecognizer:scroll];
  _scrollPan = scroll;

  // On-phone desktop only: pinch zooms the desktop, a long press
  // right-clicks where the finger is.
  UIPinchGestureRecognizer* pinch =
      [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handlePinch:)];
  pinch.enabled = NO;
  pinch.delegate = self;
  [self addGestureRecognizer:pinch];
  _pinch = pinch;
  UILongPressGestureRecognizer* longPress =
      [[UILongPressGestureRecognizer alloc]
          initWithTarget:self
                  action:@selector(handleLongPress:)];
  longPress.enabled = NO;
  longPress.delegate = self;
  [self addGestureRecognizer:longPress];
  _longPress = longPress;

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

- (void)layoutSubviews {
  [super layoutSubviews];
  [self layoutPhoneDesktop:NO];
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  [self setNeedsLayout];
}

// With a monitor the desktop lives there and this view is its trackpad.
// Without one the desktop moves onto this phone's own screen (on-phone
// desktop) and this view becomes a transparent touch layer above it.
- (void)refreshExternalState {
  const BOOL external = ExternalScene() != nil;
  const BOOL phone = !external && self.window.windowScene != nil;
  const BOOL mode_changed = phone != _phoneMode;
  _phoneMode = phone;
  if (mode_changed) {
    [self stopFling];
    _cursorPlaced = NO;
    _pointerSeen = NO;
    NSLog(@"[DeskBrowser] desktop mode=%@", phone ? @"phone" : @"external");
  }
  [self applyModeAppearance];
  if (phone) {
    [self layoutPhoneDesktop:mode_changed];
  } else if (mode_changed) {
    display::SetPhoneDesktopForIOS(display::PhoneDesktopForIOS());
    views::NativeWidgetIOS::ExternalSceneGeometryChanged();
  }
  if (mode_changed) {
    [self updateOrientationLock];
    [self.window.rootViewController setNeedsStatusBarAppearanceUpdate];
  }
  UIWindowScene* scene = [self desktopScene];
  self.userInteractionEnabled = scene != nil;
  if (!scene) {
    if (self.isFirstResponder) {
      [self resignFirstResponder];
    }
    _cursorWindow.hidden = YES;
    _cursorWindow = nil;
    _cursorPlaced = NO;
    return;
  }
  if (_cursorWindow.windowScene != scene) {
    _cursorWindow.hidden = YES;
    _cursorWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _cursorWindow.windowLevel = UIWindowLevelAlert + 100;
    _cursorWindow.userInteractionEnabled = NO;
    _cursorWindow.backgroundColor = UIColor.clearColor;
    _cursorWindow.rootViewController =
        [[ChromeViewsIOSCursorWindowController alloc] init];
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
    NSLog(@"[DeskBrowser] trackpad attached desktop=%@ scale=%.1f "
          @"phone=%@ mode=%@",
          NSStringFromCGRect([self desktopBounds]), scene.screen.scale,
          NSStringFromCGRect(self.bounds), _phoneMode ? @"phone" : @"external");
  }
  // The cursor overlay covers the monitor, or the whole panel on the phone.
  _cursorWindow.frame =
      _phoneMode ? scene.coordinateSpace.bounds : DesktopBounds(scene);
  if (!_cursorPlaced) {
    CGRect desktop = [self desktopBounds];
    _cursor = CGPointMake(CGRectGetMidX(desktop), CGRectGetMidY(desktop));
    _cursorPlaced = YES;
  }
  [self placeCursor];
  if (!self.isFirstResponder && self.window) {
    [self becomeFirstResponder];
  }
}

- (void)placeCursor {
  display::UpdateCursorScreenPointForIOS(gfx::Point(_cursor.x, _cursor.y));
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (_phoneMode) {
    const views_trackpad_ios::Point p =
        views_trackpad_ios::DesktopToPanel(_viewport, {_cursor.x, _cursor.y});
    _cursorLayer.position = CGPointMake(p.x, p.y);
    _cursorLayer.hidden = !_pointerSeen;
  } else {
    _cursorLayer.position = _cursor;
    _cursorLayer.hidden = NO;
  }
  [CATransaction commit];
}

#pragma mark - On-phone desktop

// The scene the desktop is on: the external display's, or with none, this
// phone's own.
- (UIWindowScene*)desktopScene {
  if (UIWindowScene* external = ExternalScene()) {
    return external;
  }
  return _phoneMode ? self.window.windowScene : nil;
}

// The desktop in desktop DIPs (the primary display's bounds).
- (CGRect)desktopBounds {
  if (_phoneMode) {
    return CGRectMake(0, 0, _desktop.width, _desktop.height);
  }
  return DesktopBounds(ExternalScene());
}

// The cursor in |view|'s coordinates. On the phone the cursor's desktop
// point is first mapped onto the panel through the viewport.
- (CGPoint)convertCursorTo:(UIView*)view {
  if (_phoneMode) {
    const views_trackpad_ios::Point p =
        views_trackpad_ios::DesktopToPanel(_viewport, {_cursor.x, _cursor.y});
    return [view convertPoint:CGPointMake(p.x, p.y) fromCoordinateSpace:self];
  }
  return [view convertPoint:_cursor
        fromCoordinateSpace:view.window.screen.coordinateSpace];
}

- (void)applyModeAppearance {
  if (!_phoneMode) {
    [self setRotateHint:NO];
  }
  const BOOL external = ExternalScene() != nil;
  _hint.hidden = _phoneMode && !_rotateHint;
  _hint.text = _rotateHint ? kRotateHint
                           : (external ? kTrackpadHint : kConnectDisplayHint);
  self.backgroundColor =
      _rotateHint  ? UIColor.blackColor
      : _phoneMode ? UIColor.clearColor
                   : [UIColor colorWithWhite:0.08 alpha:1];
  _keyboardButton.hidden = _rotateHint || !(external || _phoneMode);
  _keyboardButton.backgroundColor =
      _phoneMode ? [UIColor colorWithWhite:0 alpha:0.45] : UIColor.clearColor;
  _keyboardButton.layer.cornerRadius = 22;
  _pinch.enabled = _phoneMode;
  _longPress.enabled = _phoneMode;
  UIWindow* window = self.window;
  if (!window) {
    return;
  }
  // On the phone this window floats, transparent, above the desktop's
  // windows to take every touch and stay key (hardware keys and the
  // on-screen keyboard), and display::Screen skips it.
  window.tag = display::kPhoneInputOverlayWindowTagForIOS;
  window.windowLevel =
      _phoneMode ? UIWindowLevelNormal + 100 : UIWindowLevelNormal;
  window.opaque = !_phoneMode;
  window.backgroundColor =
      _phoneMode ? UIColor.clearColor : UIColor.blackColor;
  window.rootViewController.view.backgroundColor =
      _phoneMode ? UIColor.clearColor : UIColor.blackColor;
}

// Sizes the desktop for the panel and fits it. Only a new desktop size
// re-lays out Chrome; a new safe area only re-places it.
- (void)layoutPhoneDesktop:(BOOL)force {
  if (!_phoneMode || CGRectIsEmpty(self.bounds)) {
    [self setRotateHint:NO];
    return;
  }
  // The orientation lock should keep a tall phone in landscape. If iOS shows
  // portrait anyway, never re-lay out the desktop for it.
  if (!PanelMayRotate() && self.bounds.size.height > self.bounds.size.width) {
    [self setRotateHint:YES];
    if (_desktop.width > 0 && !force) {
      return;
    }
    // First layout in portrait: size the desktop for the landscape panel it
    // will get once iOS applies the lock.
  } else {
    [self setRotateHint:NO];
  }
  const UIEdgeInsets safe = self.safeAreaInsets;
  // Top inset included: where iOS keeps showing status (the Duo's status
  // capsule) it must sit above Chromium, never over it. Bottom inset left
  // out: the home indicator is a thin overlay over page content.
  views_trackpad_ios::Extent usable{
      safe.left, safe.top, self.bounds.size.width - safe.left - safe.right,
      self.bounds.size.height - safe.top};
  NSLog(@"[DeskBrowser] phone panel %@ safe %@ statusbar hidden=%d frame=%@ "
        @"level=%.0f",
        NSStringFromCGSize(self.bounds.size), NSStringFromUIEdgeInsets(safe),
        self.window.windowScene.statusBarManager.statusBarHidden,
        NSStringFromCGRect(self.window.windowScene.statusBarManager.statusBarFrame),
        self.window.windowLevel);
  if (_rotateHint) {
    // Landscape-right: the panel's long side across, the side safe areas
    // where portrait has its top and bottom ones.
    usable = {safe.top, 0, self.bounds.size.height - safe.top - safe.bottom,
              self.bounds.size.width};
  }
  const views_trackpad_ios::Extent desktop =
      views_trackpad_ios::PhoneDesktopSize(usable);
  const bool size_changed = force || !SameExtent(desktop, _desktop);
  if (!size_changed && SameExtent(usable, _usable)) {
    return;
  }
  _usable = usable;
  _desktop = desktop;
  _viewport = size_changed
                  ? views_trackpad_ios::FitViewport(usable, desktop)
                  : views_trackpad_ios::ClampViewport(_viewport, usable,
                                                      desktop);
  [self publishPhoneDesktop];
  NSLog(@"[DeskBrowser] phone desktop %.0fx%.0f zoom=%.3f origin={%.1f, "
        @"%.1f} panel=%@",
        desktop.width, desktop.height, _viewport.zoom, _viewport.origin.x,
        _viewport.origin.y, NSStringFromCGRect(self.bounds));
  if (size_changed) {
    CGRect bounds = [self desktopBounds];
    _cursor = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    views::NativeWidgetIOS::ExternalSceneGeometryChanged();
  } else {
    views::NativeWidgetIOS::PhoneDesktopViewportChanged();
  }
  if (_cursorWindow) {
    _cursorWindow.frame = self.window.windowScene.coordinateSpace.bounds;
  }
  [self placeCursor];
}

- (void)setRotateHint:(BOOL)on {
  if (_rotateHint == on) {
    return;
  }
  _rotateHint = on;
  NSLog(@"[DeskBrowser] rotate-to-landscape screen %@", on ? @"on" : @"off");
  // Opaque, above the desktop's windows (this window floats over them).
  self.backgroundColor =
      on ? UIColor.blackColor
         : (_phoneMode ? UIColor.clearColor
                       : [UIColor colorWithWhite:0.08 alpha:1]);
  _hint.text = on ? kRotateHint
                  : (ExternalScene() ? kTrackpadHint : kConnectDisplayHint);
  _hint.hidden = _phoneMode && !on;
  _keyboardButton.hidden = on || !(_phoneMode || ExternalScene());
  if (on) {
    [self setSoftKeyboardShown:NO];
    [self stopFling];
    [self updateOrientationLock];
  }
}

- (void)publishPhoneDesktop {
  display::PhoneDesktopForIOS desktop;
  desktop.active = true;
  desktop.size = gfx::Size(_desktop.width, _desktop.height);
  desktop.origin = gfx::PointF(_viewport.origin.x, _viewport.origin.y);
  desktop.zoom = _viewport.zoom;
  desktop.landscape_right_only = !PanelMayRotate();
  display::SetPhoneDesktopForIOS(desktop);
}

- (void)viewportChanged {
  [self publishPhoneDesktop];
  views::NativeWidgetIOS::PhoneDesktopViewportChanged();
  [self placeCursor];
}

- (void)updateOrientationLock {
  UIWindowScene* scene = self.window.windowScene;
  // Every window on the phone scene (this one and the desktop's) answers
  // with the same mask.
  for (UIWindow* window in scene.windows) {
    [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    [window.rootViewController setNeedsStatusBarAppearanceUpdate];
  }
  const UIInterfaceOrientationMask mask = ChromeViewsIOSPhoneOrientations();
  if (!scene || mask != UIInterfaceOrientationMaskLandscapeRight) {
    // Unlocking only needs the controller's new mask.
    return;
  }
  UIWindowSceneGeometryPreferencesIOS* preferences =
      [[UIWindowSceneGeometryPreferencesIOS alloc]
          initWithInterfaceOrientations:mask];
  [scene requestGeometryUpdateWithPreferences:preferences
                                 errorHandler:^(NSError* error) {
                                   NSLog(@"[DeskBrowser] orientation lock: %@",
                                         error);
                                 }];
}

// Moves the cursor to where a touch or the iOS pointer is on the panel.
- (void)moveCursorToPanelPoint:(CGPoint)panel {
  const views_trackpad_ios::Point d =
      views_trackpad_ios::PanelToDesktop(_viewport, {panel.x, panel.y});
  [self moveCursorByDIPs:CGPointMake(d.x - _cursor.x, d.y - _cursor.y)];
}

- (void)handlePinch:(UIPinchGestureRecognizer*)pinch {
  if (!_phoneMode) {
    return;
  }
  if (pinch.state == UIGestureRecognizerStateBegan) {
    _lastPinchScale = 1;
  }
  if (pinch.numberOfTouches < 2 || pinch.scale <= 0) {
    return;
  }
  const CGFloat factor = pinch.scale / _lastPinchScale;
  _lastPinchScale = pinch.scale;
  const CGPoint anchor = [pinch locationInView:self];
  _viewport = views_trackpad_ios::PinchViewport(
      _viewport, {anchor.x, anchor.y}, factor, {0, 0}, _usable, _desktop);
  [self viewportChanged];
}

// Two fingers move a zoomed-in desktop around the panel.
- (void)panViewport:(UIPanGestureRecognizer*)pan {
  const CGPoint t = [pan translationInView:self];
  if (pan.state == UIGestureRecognizerStateBegan) {
    _lastViewportPan = CGPointZero;
  }
  const views_trackpad_ios::Point delta{t.x - _lastViewportPan.x,
                                        t.y - _lastViewportPan.y};
  _lastViewportPan = t;
  _viewport = views_trackpad_ios::PinchViewport(_viewport, {0, 0}, 1, delta,
                                                _usable, _desktop);
  [self viewportChanged];
}

- (void)handleLongPress:(UILongPressGestureRecognizer*)press {
  if (!_phoneMode || press.state != UIGestureRecognizerStateBegan) {
    return;
  }
  _longPressFired = YES;
  [self moveCursorToPanelPoint:[press locationInView:self]];
  // While a menu is open its nested run loop can deliver a quick tap's
  // touch-up late enough to look like a long press; there a press is a
  // plain click (pick an item or dismiss), never a second context menu.
  const int button = views::NativeWidgetIOS::GetCaptureWindow().Get()
                         ? ui::EF_LEFT_MOUSE_BUTTON
                         : ui::EF_RIGHT_MOUSE_BUTTON;
  // The context menu runs a nested run loop. Open it after UIKit has
  // finished with this gesture so the next touch starts a fresh one.
  __weak ChromeViewsIOSTrackpadView* weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf clickWithButton:button];
  });
}

// One finger scrolls what is under it, following the finger, with a fling.
- (void)scrollUnderFinger:(UIPanGestureRecognizer*)pan {
  const CGPoint t = [pan translationInView:self];
  if (pan.state == UIGestureRecognizerStateBegan) {
    [self stopFling];
    _lastPan = CGPointZero;
    const CGPoint at = [pan locationInView:self];
    [self moveCursorToPanelPoint:CGPointMake(at.x - t.x, at.y - t.y)];
  }
  const CGFloat zoom = _viewport.zoom > 0 ? _viewport.zoom : 1;
  const CGPoint delta = CGPointMake((t.x - _lastPan.x) / zoom,
                                    (t.y - _lastPan.y) / zoom);
  _lastPan = t;
  const BOOL ended = pan.state == UIGestureRecognizerStateEnded;
  if (pan.state == UIGestureRecognizerStateBegan) {
    [self wheelBy:delta phase:0];
  } else if (ended || pan.state == UIGestureRecognizerStateCancelled) {
    [self wheelBy:delta phase:1];
    const CGPoint v = [pan velocityInView:self];
    if (ended && std::hypot(v.x, v.y) > kFlingStopSpeed * 4) {
      [self startFlingWithVelocity:v];
    } else {
      [self wheelBy:CGPointZero phase:2];
    }
  } else {
    [self wheelBy:delta phase:1];
  }
}

- (void)startFlingWithVelocity:(CGPoint)velocity {
  [self stopFling];
  _flingVelocity = velocity;
  _flingLast = CACurrentMediaTime();
  _fling = [CADisplayLink displayLinkWithTarget:self
                                       selector:@selector(flingStep:)];
  [_fling addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)flingStep:(CADisplayLink*)link {
  const CFTimeInterval now = CACurrentMediaTime();
  const CGFloat dt = std::min(now - _flingLast, 0.05);
  _flingLast = now;
  const CGFloat decay = std::pow(kFlingDecayPerFrame, dt * 60);
  _flingVelocity = CGPointMake(_flingVelocity.x * decay,
                               _flingVelocity.y * decay);
  if (std::hypot(_flingVelocity.x, _flingVelocity.y) < kFlingStopSpeed ||
      !_phoneMode) {
    [self stopFling];
    return;
  }
  const CGFloat zoom = _viewport.zoom > 0 ? _viewport.zoom : 1;
  [self wheelBy:CGPointMake(_flingVelocity.x * dt / zoom,
                            _flingVelocity.y * dt / zoom)
          phase:1];
}

- (void)stopFling {
  if (!_fling) {
    return;
  }
  [_fling invalidate];
  _fling = nil;
  [self wheelBy:CGPointZero phase:2];
}

// After a click on the phone, raise the on-screen keyboard when the click
// focused something that takes text (a web input or a Views textfield such
// as the omnibox), and lower it otherwise.
- (void)updateSoftKeyboardAfterClick {
  __weak ChromeViewsIOSTrackpadView* weakSelf = self;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW,
                    static_cast<int64_t>(kKeyboardCheckDelaySeconds *
                                         NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        ChromeViewsIOSTrackpadView* strongSelf = weakSelf;
        if (strongSelf && strongSelf->_phoneMode) {
          [strongSelf setSoftKeyboardShown:[strongSelf focusTakesText]];
        }
      });
}

- (BOOL)focusTakesText {
  if (UIView* web = _keyWebView) {
    return [web respondsToSelector:@selector(deskBrowserIsEditable)] &&
           [(id<ChromeViewsIOSWebInput>)web deskBrowserIsEditable];
  }
  views::NativeWidgetIOS* native = views::NativeWidgetIOS::GetFromNativeWindow(
      gfx::NativeWindow(_keyWidgetWindow));
  views::Widget* widget = native ? native->GetWidget() : nullptr;
  views::FocusManager* focus = widget ? widget->GetFocusManager() : nullptr;
  views::View* focused = focus ? focus->GetFocusedView() : nullptr;
  return focused && views::IsViewClass<views::Textfield>(focused);
}

- (void)setSoftKeyboardShown:(BOOL)shown {
  if (_softKeyboard == shown) {
    return;
  }
  _softKeyboard = shown;
  if (!self.isFirstResponder) {
    [self becomeFirstResponder];
  }
  [self reloadInputViews];
}

#pragma mark - Hit testing and dispatch

// Front-most widget window under the cursor, and the UIView hit inside it.
- (UIWindow*)widgetWindowAtCursor:(UIView**)hitView {
  // A menu must get clicks even outside its bounds (to cancel itself), and
  // drags must keep targeting their capture widget instead of the page below.
  UIWindow* capture = views::NativeWidgetIOS::GetCaptureWindow().Get();
  if (capture && !capture.hidden && capture.windowScene == [self desktopScene]) {
    if (hitView) {
      *hitView = capture.rootViewController.view;
    }
    return capture;
  }
  UIWindowScene* scene = [self desktopScene];
  if (!scene) {
    return nil;
  }
  for (UIWindow* window in WidgetWindowsFrontToBack(scene)) {
    CGPoint p = [self convertCursorTo:window];
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
  CGPoint p = [self convertCursorTo:window];
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
  return [self convertCursorTo:view];
}

// Sets the cursor, clamped to the whole external display in desktop DIPs.
- (BOOL)setCursorClamped:(views_trackpad_ios::Point)p {
  if (![self desktopScene]) {
    return NO;
  }
  const views_trackpad_ios::Point c =
      views_trackpad_ios::ClampToDisplay(p, ExtentOf([self desktopBounds]));
  _cursor = CGPointMake(c.x, c.y);
  [self placeCursor];
  return YES;
}

// Relative motion in desktop DIPs; the only way the cursor moves.
- (void)moveCursorByDIPs:(CGPoint)delta {
  if (![self setCursorClamped:views_trackpad_ios::Point{_cursor.x + delta.x,
                                                     _cursor.y + delta.y}]) {
    return;
  }
  [self hoverAtCursor];
}

- (void)hoverAtCursor {
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
  if (_phoneMode) {
    if (_movePanIsPointer) {
      // A mouse drag through the iOS pointer: the cursor follows it.
      [self moveCursorToPanelPoint:[pan locationInView:self]];
    } else {
      [self scrollUnderFinger:pan];
    }
    return;
  }
  CGPoint t = [pan translationInView:self];
  if (pan.state == UIGestureRecognizerStateBegan) {
    _lastPan = CGPointZero;
  }
  // A mouse drag through the iOS pointer is phone-bounded like hover, so it
  // gets the same full-display gain; fingers keep the trackpad gain.
  CGFloat gain = kCursorGain;
  if (_movePanIsPointer) {
    if (UIWindowScene* scene = ExternalScene()) {
      gain = views_trackpad_ios::PointerFallbackGain(
          ExtentOf(self.bounds), ExtentOf(DesktopBounds(scene)), kCursorGain);
    }
  }
  [self moveCursorByDIPs:CGPointMake((t.x - _lastPan.x) * gain,
                                     (t.y - _lastPan.y) * gain)];
  _lastPan = t;
  if (pan.state == UIGestureRecognizerStateEnded) {
    NSLog(@"[DeskBrowser] trackpad cursor=%@", NSStringFromCGPoint(_cursor));
  }
}

- (void)handleTap:(UITapGestureRecognizer*)tap {
  if (tap.state != UIGestureRecognizerStateRecognized) {
    return;
  }
  if (_phoneMode) {
    if (_longPressFired) {
      _longPressFired = NO;
      return;
    }
    // A tap clicks where it lands.
    [self moveCursorToPanelPoint:[tap locationInView:self]];
    [self clickWithButton:ui::EF_LEFT_MOUSE_BUTTON];
    [self updateSoftKeyboardAfterClick];
    return;
  }
  [self clickWithButton:ui::EF_LEFT_MOUSE_BUTTON];
}

- (void)handleRightTap:(UITapGestureRecognizer*)tap {
  if (tap.state != UIGestureRecognizerStateRecognized) {
    return;
  }
  if (_phoneMode) {
    [self moveCursorToPanelPoint:[tap locationInView:self]];
  }
  [self clickWithButton:ui::EF_RIGHT_MOUSE_BUTTON];
}

- (void)handleScroll:(UIPanGestureRecognizer*)pan {
  if (_phoneMode && pan == _scrollPan) {
    [self panViewport:pan];
    return;
  }
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
  CGPoint p = [self convertCursorTo:window];
  gfx::Point location(p.x, p.y);
  ui::MouseWheelEvent wheel(gfx::Vector2d(delta.x, delta.y), location,
                            location, base::TimeTicks::Now(), 0, 0);
  views::NativeWidgetIOS::DispatchTrackpadMouseEvent(
      gfx::NativeWindow(window), &wheel);
}

#pragma mark - Hardware mouse

// True while GameController owns the mouse: a mouse is connected and has
// reported motion. UIKit's pointer copy of it is then ignored entirely.
- (BOOL)gcMouseActive {
  return _mice.count > 0 && _gcMouseDelivering;
}

- (void)mouseConnected:(NSNotification*)notification {
  [self attachMouse:notification.object];
}

- (void)mouseDisconnected:(NSNotification*)notification {
  GCMouse* mouse = notification.object;
  [_mice removeObject:mouse];
  if (_mice.count == 0) {
    _gcMouseDelivering = NO;
  }
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
  // The Simulator's touch injection shows up as a GCMouse; it is not a mouse.
  if ([mouse.vendorName containsString:@"touchscreen"]) {
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
      if (!strongSelf->_gcMouseDelivering) {
        NSLog(@"[DeskBrowser] GCMouse delivering; iOS pointer ignored");
        strongSelf->_gcMouseDelivering = YES;
        strongSelf->_hoverValid = NO;
      }
      strongSelf->_pointerSeen = YES;
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

// Relative hardware-mouse motion in desktop DIPs (no trackpad gain).
- (void)movePointerBy:(CGPoint)delta {
  if (_mouseButtons) {
    [self dragCursorBy:delta];
    return;
  }
  [self moveCursorByDIPs:delta];
}

- (void)dragCursorBy:(CGPoint)delta {
  if (![self setCursorClamped:views_trackpad_ios::Point{_cursor.x + delta.x,
                                                     _cursor.y + delta.y}]) {
    return;
  }
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
  CGPoint p = [self convertCursorTo:window];
  gfx::Point location(p.x, p.y);
  ui::MouseWheelEvent wheel(gfx::Vector2d(delta.x, delta.y), location,
                            location, base::TimeTicks::Now(), 0, 0);
  views::NativeWidgetIOS::DispatchTrackpadMouseEvent(
      gfx::NativeWindow(window), &wheel);
}

// Phone-side pointer fallback, used only when GameController reports nothing
// for the mouse. The iOS pointer is absolute and stops at the phone's edges,
// so only its deltas move the cursor, at a gain that lets phone-sized travel
// span the whole monitor, and resting on a phone edge pins the cursor to the
// matching monitor edge (otherwise the reachable area would be the phone's
// size times the gain, offset wherever the pointers started).
- (void)handleHover:(UIHoverGestureRecognizer*)hover {
  if ([self gcMouseActive]) {
    _hoverValid = NO;
    return;
  }
  CGPoint p = [hover locationInView:self];
  if (_phoneMode) {
    // On the phone the iOS pointer is over the desktop itself: the cursor
    // sits exactly under it.
    if (hover.state == UIGestureRecognizerStateBegan ||
        hover.state == UIGestureRecognizerStateChanged) {
      _pointerSeen = YES;
      [self moveCursorToPanelPoint:p];
    }
    return;
  }
  UIWindowScene* scene = ExternalScene();
  if (!scene) {
    _hoverValid = NO;
    return;
  }
  switch (hover.state) {
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged: {
      if (!_loggedPointerFallback) {
        NSLog(@"[DeskBrowser] mouse via iOS pointer fallback");
        _loggedPointerFallback = YES;
      }
      const views_trackpad_ios::Extent phone = ExtentOf(self.bounds);
      const views_trackpad_ios::Extent display =
          ExtentOf(DesktopBounds(scene));
      const double gain =
          views_trackpad_ios::PointerFallbackGain(phone, display, kCursorGain);
      views_trackpad_ios::Point next{_cursor.x, _cursor.y};
      if (_hoverValid) {
        next = views_trackpad_ios::MoveCursor(
            next, {(p.x - _lastHover.x) * gain, (p.y - _lastHover.y) * gain},
            display);
      }
      next = views_trackpad_ios::PinToPhoneEdges(next, {p.x, p.y}, phone,
                                                 display);
      _lastHover = p;
      _hoverValid = YES;
      if (next.x != _cursor.x || next.y != _cursor.y) {
        [self moveCursorByDIPs:CGPointMake(next.x - _cursor.x,
                                           next.y - _cursor.y)];
      }
      break;
    }
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
  if (_rotateHint) {
    return NO;
  }
  // While GameController owns the mouse, its clicks arrive there; drop the
  // duplicate indirect-pointer touches UIKit also delivers.
  if (touch.type == UITouchTypeIndirectPointer && [self gcMouseActive]) {
    return NO;
  }
  if (recognizer == _movePan) {
    _movePanIsPointer = touch.type == UITouchTypeIndirectPointer;
  }
  if (_phoneMode && touch.type == UITouchTypeDirect) {
    // A finger on the glass stops a fling.
    [self stopFling];
    if (recognizer == _longPress) {
      _longPressFired = NO;
    }
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
  // On the phone, pinch and the two-finger pan zoom and move the desktop
  // together.
  if ((a == _pinch && b == _scrollPan) || (a == _scrollPan && b == _pinch)) {
    return YES;
  }
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
  [self setSoftKeyboardShown:!_softKeyboard];
}

- (UIWindow*)keyWindowForViews {
  if (_keyWidgetWindow && !_keyWidgetWindow.hidden) {
    return _keyWidgetWindow;
  }
  UIWindowScene* scene = [self desktopScene];
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
  if (_phoneMode && ([text containsString:@"\n"] ||
                     [text containsString:@"\r"])) {
    // Return usually moves focus (omnibox -> page, a submitted form): put
    // the on-screen keyboard away unless a text field still has focus.
    [self updateSoftKeyboardAfterClick];
  }
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
