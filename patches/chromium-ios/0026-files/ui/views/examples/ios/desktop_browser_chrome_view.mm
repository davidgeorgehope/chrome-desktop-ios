// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/views/examples/ios/desktop_browser_chrome_view.h"

#include <algorithm>
#include <string>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "cc/paint/paint_flags.h"
#include "third_party/skia/include/core/SkPathBuilder.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/color/color_id.h"
#include "ui/color/color_provider.h"
#include "ui/events/base_event_utils.h"
#include "ui/events/event.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/views/background.h"
#include "ui/views/border.h"
#include "ui/views/controls/button/button.h"
#include "ui/views/controls/textfield/textfield.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/widget/widget.h"
#include "ui/views/view_class_properties.h"

namespace {

// Non-touch values from chrome/browser/ui/layout_constants.cc.
constexpr int kTabHeight = 35;
constexpr int kTabStripPadding = 6;
constexpr int kTabStripHeight = kTabHeight + kTabStripPadding;
constexpr int kTabCornerRadius = 8;
constexpr int kTabHorizontalPadding = 8;
constexpr int kDefaultTabWidth = 240;
constexpr int kMinTabWidth = 80;
constexpr int kNewTabButtonSize = 28;
constexpr int kLocationBarHeight = 34;
constexpr int kLocationBarMargin = 9;
constexpr int kToolbarHeight = kLocationBarHeight + 2 * kLocationBarMargin;
constexpr int kToolbarButtonSize = 34;
constexpr int kToolbarElementPadding = 4;

// Chromium Refresh light-theme fallbacks (kColorSys* / kColorToolbar).
constexpr SkColor kFrameFallback = SkColorSetRGB(0xDE, 0xE1, 0xE6);
constexpr SkColor kToolbarFallback = SK_ColorWHITE;
constexpr SkColor kOmniboxFallback = SkColorSetRGB(0xF1, 0xF3, 0xF4);
constexpr SkColor kTitleActiveFallback = SkColorSetRGB(0x1F, 0x1F, 0x1F);
constexpr SkColor kTitleInactiveFallback = SkColorSetRGB(0x44, 0x47, 0x46);
constexpr SkColor kIconFallback = SkColorSetRGB(0x44, 0x47, 0x46);
constexpr SkColor kIconDisabledFallback = SkColorSetRGB(0xB0, 0xB0, 0xB0);

SkColor ColorOr(const ui::ColorProvider* provider,
                ui::ColorId id,
                SkColor fallback) {
  if (!provider) {
    return fallback;
  }
  const SkColor color = provider->GetColor(id);
  return color ? color : fallback;
}

gfx::FontList TabFont() {
  return gfx::FontList(gfx::FontList().DeriveWithSizeDelta(
      12 - gfx::FontList().GetFontSize()));
}

gfx::FontList OmniboxFont() {
  return gfx::FontList(gfx::FontList().DeriveWithSizeDelta(
      14 - gfx::FontList().GetFontSize()));
}

}  // namespace

// ---------------------------------------------------------------------------
// Icon button that paints a simple geometric chrome-style glyph.
// ---------------------------------------------------------------------------

class ChromeIconButton : public views::Button {
  METADATA_HEADER(ChromeIconButton, views::Button)

 public:
  enum class Glyph { kBack, kForward, kReload, kMenu, kNewTab, kClose };

  ChromeIconButton(Glyph glyph,
                   std::u16string accessible_name,
                   PressedCallback callback)
      : views::Button(std::move(callback)), glyph_(glyph) {
    SetPreferredSize(gfx::Size(kToolbarButtonSize, kToolbarButtonSize));
    SetFocusBehavior(FocusBehavior::ACCESSIBLE_ONLY);
    SetAccessibleName(std::move(accessible_name));
  }

  void SetGlyphColor(SkColor color) { color_ = color; SchedulePaint(); }
  void SetEnabledGlyph(bool enabled) {
    SetEnabled(enabled);
    SchedulePaint();
  }

 private:
  void PaintButtonContents(gfx::Canvas* canvas) override {
    const SkColor color = GetEnabled() ? color_ : kIconDisabledFallback;
    cc::PaintFlags flags;
    flags.setColor(color);
    flags.setAntiAlias(true);
    flags.setStyle(cc::PaintFlags::kStroke_Style);
    flags.setStrokeWidth(1.75f);
    flags.setStrokeCap(cc::PaintFlags::kRound_Cap);
    flags.setStrokeJoin(cc::PaintFlags::kRound_Join);

    const gfx::Rect local = GetLocalBounds();
    const float cx = local.width() / 2.0f;
    const float cy = local.height() / 2.0f;
    const float r = 6.0f;

    SkPathBuilder path;
    switch (glyph_) {
      case Glyph::kBack:
        path.moveTo(cx + 3.5f, cy - r);
        path.lineTo(cx - 3.5f, cy);
        path.lineTo(cx + 3.5f, cy + r);
        canvas->DrawPath(path.detach(), flags);
        break;
      case Glyph::kForward:
        path.moveTo(cx - 3.5f, cy - r);
        path.lineTo(cx + 3.5f, cy);
        path.lineTo(cx - 3.5f, cy + r);
        canvas->DrawPath(path.detach(), flags);
        break;
      case Glyph::kReload: {
        SkRect oval = SkRect::MakeXYWH(cx - r, cy - r, 2 * r, 2 * r);
        canvas->sk_canvas()->drawArc(oval, 40, 280, flags);
        // Arrow head.
        flags.setStyle(cc::PaintFlags::kFill_Style);
        SkPathBuilder head;
        head.moveTo(cx + r - 0.5f, cy - 2);
        head.lineTo(cx + r + 3.5f, cy + 2);
        head.lineTo(cx + r - 4.0f, cy + 2.5f);
        head.close();
        canvas->DrawPath(head.detach(), flags);
        break;
      }
      case Glyph::kMenu:
        flags.setStrokeWidth(2.0f);
        for (int i = -1; i <= 1; ++i) {
          canvas->DrawLine(gfx::PointF(cx - 6, cy + i * 5),
                           gfx::PointF(cx + 6, cy + i * 5), flags);
        }
        break;
      case Glyph::kNewTab:
        flags.setStrokeWidth(2.0f);
        canvas->DrawLine(gfx::PointF(cx, cy - 6), gfx::PointF(cx, cy + 6),
                         flags);
        canvas->DrawLine(gfx::PointF(cx - 6, cy), gfx::PointF(cx + 6, cy),
                         flags);
        break;
      case Glyph::kClose:
        flags.setStrokeWidth(1.6f);
        canvas->DrawLine(gfx::PointF(cx - 4, cy - 4),
                         gfx::PointF(cx + 4, cy + 4), flags);
        canvas->DrawLine(gfx::PointF(cx + 4, cy - 4),
                         gfx::PointF(cx - 4, cy + 4), flags);
        break;
    }
  }

  Glyph glyph_;
  SkColor color_ = kIconFallback;
};

// ---------------------------------------------------------------------------
// Tab strip
// ---------------------------------------------------------------------------

struct TabData {
  std::u16string title;
  bool active = false;
};

class DesktopBrowserChromeView::TabStripBar : public views::View {
  METADATA_HEADER(TabStripBar, views::View)

 public:
  explicit TabStripBar(base::RepeatingCallback<void(int)> tab_selected)
      : tab_selected_(std::move(tab_selected)) {
    SetPreferredSize(gfx::Size(1, kTabStripHeight));
    tabs_.push_back({u"New Tab", true});
    tabs_.push_back({u"Welcome", false});
    new_tab_ = AddChildView(std::make_unique<ChromeIconButton>(
        ChromeIconButton::Glyph::kNewTab, u"New tab",
        base::BindRepeating(&TabStripBar::AddTab, base::Unretained(this))));
  }

  const std::vector<TabData>& tabs() const { return tabs_; }

  int active_index() const {
    for (size_t i = 0; i < tabs_.size(); ++i) {
      if (tabs_[i].active) {
        return static_cast<int>(i);
      }
    }
    return 0;
  }

  void SelectTab(int index) {
    if (index < 0 || static_cast<size_t>(index) >= tabs_.size()) {
      return;
    }
    for (size_t i = 0; i < tabs_.size(); ++i) {
      tabs_[i].active = static_cast<int>(i) == index;
    }
    SchedulePaint();
    if (tab_selected_) {
      tab_selected_.Run(index);
    }
  }

  void SetActiveTitle(const std::u16string& title) {
    const int i = active_index();
    if (i >= 0) {
      tabs_[i].title = title;
      SchedulePaint();
    }
  }

  void SetColors(SkColor frame, SkColor toolbar, SkColor icon) {
    frame_ = frame;
    toolbar_ = toolbar;
    if (new_tab_) {
      new_tab_->SetGlyphColor(icon);
    }
    SchedulePaint();
  }

 private:
  void AddTab() {
    for (auto& tab : tabs_) {
      tab.active = false;
    }
    tabs_.push_back({u"New Tab", true});
    SchedulePaint();
    if (tab_selected_) {
      tab_selected_.Run(active_index());
    }
  }

  std::vector<gfx::Rect> TabRects() const {
    std::vector<gfx::Rect> rects;
    const int available =
        std::max(0, width() - kNewTabButtonSize - 2 * kTabStripPadding - 8);
    const int count = static_cast<int>(tabs_.size());
    if (count == 0) {
      return rects;
    }
    int tab_w = std::min(kDefaultTabWidth, available / count);
    tab_w = std::max(tab_w, kMinTabWidth);
    int x = kTabStripPadding;
    const int y = kTabStripPadding;
    const int h = kTabHeight;
    for (int i = 0; i < count; ++i) {
      rects.emplace_back(x, y, tab_w, h);
      x += tab_w - 4;  // slight overlap, like Chrome
    }
    return rects;
  }

  void Layout(PassKey) override {
    const auto rects = TabRects();
    if (new_tab_) {
      int x = kTabStripPadding;
      if (!rects.empty()) {
        x = rects.back().right() + 6;
      }
      const int y =
          kTabStripPadding + (kTabHeight - kNewTabButtonSize) / 2;
      new_tab_->SetBounds(x, y, kNewTabButtonSize, kNewTabButtonSize);
    }
  }

  void OnPaint(gfx::Canvas* canvas) override {
    views::View::OnPaint(canvas);
    canvas->FillRect(GetLocalBounds(), frame_);
    const auto rects = TabRects();
    // Paint inactive first, then the active tab on top.
    for (int pass = 0; pass < 2; ++pass) {
      for (size_t i = 0; i < tabs_.size() && i < rects.size(); ++i) {
        const bool active = tabs_[i].active;
        if (static_cast<int>(active) != pass) {
          continue;
        }
        PaintTab(canvas, rects[i], tabs_[i].title, active);
      }
    }
  }

  void PaintTab(gfx::Canvas* canvas,
                const gfx::Rect& rect,
                const std::u16string& title,
                bool active) {
    const SkColor fill = active ? toolbar_ : frame_;
    const float r = kTabCornerRadius;
    gfx::Rect body = rect;
    if (!active) {
      body.Inset(gfx::Insets::TLBR(2, 2, 3, 2));
    } else {
      // Overlap the toolbar by 1px so the tab merges into it.
      body.set_height(body.height() + 1);
    }

    SkPathBuilder path;
    const float l = body.x();
    const float t = body.y();
    const float rt = body.right();
    const float b = body.bottom();
    // Bottom-left ear, top edge, bottom-right ear — Chrome Refresh tab.
    path.moveTo(l - r, b);
    path.cubicTo(l - r * 0.15f, b, l, b - r * 0.15f, l, b - r);
    path.lineTo(l, t + r);
    path.cubicTo(l, t + r * 0.45f, l + r * 0.45f, t, l + r, t);
    path.lineTo(rt - r, t);
    path.cubicTo(rt - r * 0.45f, t, rt, t + r * 0.45f, rt, t + r);
    path.lineTo(rt, b - r);
    path.cubicTo(rt, b - r * 0.15f, rt + r * 0.15f, b, rt + r, b);
    path.close();

    cc::PaintFlags flags;
    flags.setAntiAlias(true);
    flags.setStyle(cc::PaintFlags::kFill_Style);
    flags.setColor(active ? fill : SkColorSetA(kTitleInactiveFallback, 0x28));
    canvas->DrawPath(path.detach(), flags);

    const SkColor title_color =
        active ? kTitleActiveFallback : kTitleInactiveFallback;
    const int text_x = body.x() + kTabHorizontalPadding;
    const int text_w = body.width() - 2 * kTabHorizontalPadding - (active ? 16 : 0);
    canvas->DrawStringRectWithFlags(
        title, TabFont(), title_color,
        gfx::Rect(text_x, body.y(), std::max(0, text_w), body.height() - 1),
        gfx::Canvas::TEXT_ALIGN_LEFT | gfx::Canvas::NO_ELLIPSIS);

    if (active) {
      // Close affordance.
      cc::PaintFlags xf;
      xf.setAntiAlias(true);
      xf.setColor(title_color);
      xf.setStyle(cc::PaintFlags::kStroke_Style);
      xf.setStrokeWidth(1.4f);
      xf.setStrokeCap(cc::PaintFlags::kRound_Cap);
      const float cx = body.right() - 14;
      const float cy = body.CenterPoint().y();
      canvas->DrawLine(gfx::PointF(cx - 3.5f, cy - 3.5f),
                       gfx::PointF(cx + 3.5f, cy + 3.5f), xf);
      canvas->DrawLine(gfx::PointF(cx + 3.5f, cy - 3.5f),
                       gfx::PointF(cx - 3.5f, cy + 3.5f), xf);
    }
  }

  bool OnMousePressed(const ui::MouseEvent& event) override {
    const auto rects = TabRects();
    for (size_t i = 0; i < rects.size(); ++i) {
      if (rects[i].Contains(event.location())) {
        SelectTab(static_cast<int>(i));
        return true;
      }
    }
    return views::View::OnMousePressed(event);
  }

  std::vector<TabData> tabs_;
  raw_ptr<ChromeIconButton> new_tab_ = nullptr;
  base::RepeatingCallback<void(int)> tab_selected_;
  SkColor frame_ = kFrameFallback;
  SkColor toolbar_ = kToolbarFallback;
};

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class DesktopBrowserChromeView::ToolbarBar : public views::View {
  METADATA_HEADER(ToolbarBar, views::View)

 public:
  ToolbarBar() {
    SetPreferredSize(gfx::Size(1, kToolbarHeight));
    auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal,
        gfx::Insets::VH(kLocationBarMargin, kToolbarElementPadding + 4),
        kToolbarElementPadding));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);

    back_ = AddChildView(std::make_unique<ChromeIconButton>(
        ChromeIconButton::Glyph::kBack, u"Back",
        views::Button::PressedCallback()));
    back_->SetEnabledGlyph(false);
    forward_ = AddChildView(std::make_unique<ChromeIconButton>(
        ChromeIconButton::Glyph::kForward, u"Forward",
        views::Button::PressedCallback()));
    forward_->SetEnabledGlyph(false);
    reload_ = AddChildView(std::make_unique<ChromeIconButton>(
        ChromeIconButton::Glyph::kReload, u"Reload",
        views::Button::PressedCallback()));

    omnibox_ = AddChildView(std::make_unique<views::Textfield>());
    omnibox_->SetFontList(OmniboxFont());
    omnibox_->SetPlaceholderText(u"Search Google or type a URL");
    omnibox_->SetAccessibleName(u"Address and search bar");
    layout->SetFlexForView(omnibox_, 1);

    menu_ = AddChildView(std::make_unique<ChromeIconButton>(
        ChromeIconButton::Glyph::kMenu, u"Customize and control Chrome",
        views::Button::PressedCallback()));
  }

  views::Textfield* omnibox() { return omnibox_; }

  void SetColors(SkColor toolbar, SkColor omnibox, SkColor icon) {
    toolbar_ = toolbar;
    SetBackground(views::CreateSolidBackground(toolbar));
    if (omnibox_) {
      omnibox_->SetBackgroundColor(omnibox);
      omnibox_->SetBorder(views::CreateRoundedRectBorder(
          1, 12, SkColorSetRGB(0xDA, 0xDC, 0xE0)));
    }
    for (ChromeIconButton* b :
         {back_.get(), forward_.get(), reload_.get(), menu_.get()}) {
      if (b) {
        b->SetGlyphColor(icon);
      }
    }
    SchedulePaint();
  }

  void SetOmniboxText(const std::u16string& text) {
    if (omnibox_) {
      omnibox_->SetText(text);
    }
  }

 private:
  void Layout(PassKey) override {
    LayoutSuperclass<views::View>(this);
    if (omnibox_) {
      gfx::Rect b = omnibox_->bounds();
      b.set_height(kLocationBarHeight);
      b.set_y((height() - kLocationBarHeight) / 2);
      omnibox_->SetBoundsRect(b);
    }
  }

  raw_ptr<ChromeIconButton> back_ = nullptr;
  raw_ptr<ChromeIconButton> forward_ = nullptr;
  raw_ptr<ChromeIconButton> reload_ = nullptr;
  raw_ptr<ChromeIconButton> menu_ = nullptr;
  raw_ptr<views::Textfield> omnibox_ = nullptr;
  SkColor toolbar_ = kToolbarFallback;
};

// ---------------------------------------------------------------------------
// Contents pane
// ---------------------------------------------------------------------------

class DesktopBrowserChromeView::ContentsPane : public views::View {
  METADATA_HEADER(ContentsPane, views::View)

 public:
  ContentsPane() {
    SetBackground(views::CreateSolidBackground(SK_ColorWHITE));
    SetBorder(views::CreateSolidSidedBorder(
        gfx::Insets::TLBR(1, 0, 0, 0), SkColorSetRGB(0xDA, 0xDC, 0xE0)));
  }

  void SetMessage(const std::u16string& message) {
    message_ = message;
    SchedulePaint();
  }

 private:
  void OnPaint(gfx::Canvas* canvas) override {
    views::View::OnPaint(canvas);
    canvas->DrawStringRectWithFlags(
        message_, OmniboxFont(), SkColorSetRGB(0x80, 0x80, 0x80),
        gfx::Rect(0, 0, width(), height()),
        gfx::Canvas::TEXT_ALIGN_CENTER);
  }

  std::u16string message_ = u"Web contents will load here";
};

// ---------------------------------------------------------------------------
// Software cursor overlay (phone trackpad).
// ---------------------------------------------------------------------------

class DesktopBrowserChromeView::CursorOverlay : public views::View {
  METADATA_HEADER(CursorOverlay, views::View)

 public:
  CursorOverlay() {
    SetCanProcessEventsWithinSubtree(false);
    SetPreferredSize(gfx::Size(18, 18));
  }

 private:
  void OnPaint(gfx::Canvas* canvas) override {
    cc::PaintFlags flags;
    flags.setAntiAlias(true);
    // Simple arrow cursor.
    SkPathBuilder path;
    path.moveTo(1, 1);
    path.lineTo(1, 16);
    path.lineTo(5, 12);
    path.lineTo(8.5f, 17);
    path.lineTo(10.5f, 16);
    path.lineTo(7, 11);
    path.lineTo(13, 11);
    path.close();
    flags.setStyle(cc::PaintFlags::kFill_Style);
    flags.setColor(SK_ColorWHITE);
    canvas->DrawPath(path.snapshot(), flags);
    flags.setStyle(cc::PaintFlags::kStroke_Style);
    flags.setStrokeWidth(1.1f);
    flags.setColor(SK_ColorBLACK);
    canvas->DrawPath(path.detach(), flags);
  }
};

// ---------------------------------------------------------------------------
// DesktopBrowserChromeView
// ---------------------------------------------------------------------------

DesktopBrowserChromeView::DesktopBrowserChromeView() {
  SetBackground(views::CreateSolidBackground(kFrameFallback));
  auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kVertical, gfx::Insets(), 0));

  tab_strip_ = AddChildView(std::make_unique<TabStripBar>(
      base::BindRepeating(&DesktopBrowserChromeView::OnTabSelected,
                          base::Unretained(this))));
  toolbar_ = AddChildView(std::make_unique<ToolbarBar>());
  contents_ = AddChildView(std::make_unique<ContentsPane>());
  layout->SetFlexForView(contents_, 1);

  cursor_view_ = AddChildView(std::make_unique<CursorOverlay>());
  cursor_view_->SetProperty(views::kViewIgnoredByLayoutKey, true);
  cursor_view_->SetVisible(false);
}

DesktopBrowserChromeView::~DesktopBrowserChromeView() = default;

void DesktopBrowserChromeView::AddedToWidget() {
  views::View::AddedToWidget();
  const ui::ColorProvider* provider = GetColorProvider();
  const SkColor frame =
      ColorOr(provider, ui::kColorSysHeader, kFrameFallback);
  const SkColor toolbar =
      ColorOr(provider, ui::kColorSysBase, kToolbarFallback);
  const SkColor omnibox =
      ColorOr(provider, ui::kColorSysSurface4, kOmniboxFallback);
  const SkColor icon =
      ColorOr(provider, ui::kColorSysOnSurfaceSecondary, kIconFallback);
  SetBackground(views::CreateSolidBackground(frame));
  tab_strip_->SetColors(frame, toolbar, icon);
  toolbar_->SetColors(toolbar, omnibox, icon);
  toolbar_->SetOmniboxText(std::u16string());
  contents_->SetMessage(u"Web contents will load here");
}

void DesktopBrowserChromeView::Layout(PassKey) {
  LayoutSuperclass<views::View>(this);
}

void DesktopBrowserChromeView::OnTrackpadMove(const gfx::Point& point_in_view,
                                              bool click) {
  if (!cursor_view_) {
    return;
  }
  cursor_view_->SetVisible(true);
  cursor_view_->SetBounds(point_in_view.x(), point_in_view.y(), 18, 18);
  views::Widget* widget = GetWidget();
  if (!widget || !widget->GetRootView()) {
    return;
  }
  gfx::Point root = point_in_view;
  ConvertPointToWidget(this, &root);
  if (click) {
    ui::MouseEvent press(ui::EventType::kMousePressed, root, root,
                         ui::EventTimeForNow(), ui::EF_LEFT_MOUSE_BUTTON,
                         ui::EF_LEFT_MOUSE_BUTTON);
    ui::MouseEvent release(ui::EventType::kMouseReleased, root, root,
                           ui::EventTimeForNow(), ui::EF_LEFT_MOUSE_BUTTON,
                           ui::EF_LEFT_MOUSE_BUTTON);
    widget->GetRootView()->OnEvent(&press);
    widget->GetRootView()->OnEvent(&release);
  } else {
    ui::MouseEvent moved(ui::EventType::kMouseMoved, root, root,
                         ui::EventTimeForNow(), 0, 0);
    widget->GetRootView()->OnEvent(&moved);
  }
}

void DesktopBrowserChromeView::OnTabSelected(int index) {
  if (!toolbar_ || !contents_ || !tab_strip_) {
    return;
  }
  const auto& tabs = tab_strip_->tabs();
  if (index < 0 || static_cast<size_t>(index) >= tabs.size()) {
    return;
  }
  toolbar_->SetOmniboxText(tabs[index].title == u"Welcome"
                               ? u"https://www.google.com"
                               : std::u16string());
  contents_->SetMessage(tabs[index].title == u"Welcome"
                            ? u"Welcome — Web contents will load here"
                            : u"Web contents will load here");
}


BEGIN_METADATA(ChromeIconButton)
END_METADATA

BEGIN_METADATA(DesktopBrowserChromeView, TabStripBar)
END_METADATA

BEGIN_METADATA(DesktopBrowserChromeView, ToolbarBar)
END_METADATA

BEGIN_METADATA(DesktopBrowserChromeView, ContentsPane)
END_METADATA

BEGIN_METADATA(DesktopBrowserChromeView, CursorOverlay)
END_METADATA

BEGIN_METADATA(DesktopBrowserChromeView)
END_METADATA
