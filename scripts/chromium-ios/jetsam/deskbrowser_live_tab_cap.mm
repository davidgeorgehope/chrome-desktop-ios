// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/browser/memory/model/deskbrowser_live_tab_cap.h"

#import <algorithm>
#import <vector>

#import "base/logging.h"
#import "base/memory/raw_ptr.h"
#import "base/memory/weak_ptr.h"
#import "base/task/sequenced_task_runner.h"
#import "ios/chrome/browser/shared/model/application_context/application_context.h"
#import "ios/chrome/browser/shared/model/browser/browser.h"
#import "ios/chrome/browser/shared/model/browser/browser_list.h"
#import "ios/chrome/browser/shared/model/browser/browser_list_factory.h"
#import "ios/chrome/browser/shared/model/profile/profile_ios.h"
#import "ios/chrome/browser/shared/model/profile/profile_manager_ios.h"
#import "ios/chrome/browser/shared/model/web_state_list/web_state_list.h"
#import "ios/chrome/browser/shared/model/web_state_list/web_state_list_observer.h"
#import "ios/web/public/navigation/navigation_manager.h"
#import "ios/web/public/web_state.h"
#import "ios/web/public/web_state_user_data.h"
#import "url/gurl.h"

namespace {

// Keep a small number of documents resident so a single-process Blink
// instance stays under the iOS jetsam limit, even with the 6 GiB
// increased-memory-limit cap.
constexpr int kMaxLiveTabs = 4;

class DiscardedTabData : public web::WebStateUserData<DiscardedTabData> {
 public:
  const GURL& url() const { return url_; }

 private:
  friend class web::WebStateUserData<DiscardedTabData>;
  DiscardedTabData(web::WebState* web_state, const GURL& url) : url_(url) {}
  GURL url_;
};

bool IsDiscarded(web::WebState* web_state) {
  return DiscardedTabData::FromWebState(web_state) != nullptr;
}

void DiscardTab(web::WebState* web_state) {
  if (!web_state || web_state->IsBeingDestroyed() || IsDiscarded(web_state)) {
    return;
  }
  if (!web_state->IsRealized()) {
    return;
  }
  const GURL url = web_state->GetVisibleURL();
  if (!url.is_valid() || url.IsAboutBlank()) {
    return;
  }
  DiscardedTabData::CreateForWebState(web_state, url);
  web::NavigationManager* nav = web_state->GetNavigationManager();
  if (nav) {
    nav->LoadURLWithParams(web::NavigationManager::WebLoadParams(GURL("about:blank")));
  }
  LOG(INFO) << "deskbrowser-jetsam: discarded tab " << url;
}

void RestoreIfDiscarded(web::WebState* web_state) {
  if (!web_state || web_state->IsBeingDestroyed()) {
    return;
  }
  DiscardedTabData* data = DiscardedTabData::FromWebState(web_state);
  if (!data) {
    return;
  }
  const GURL url = data->url();
  DiscardedTabData::RemoveFromWebState(web_state);
  web::NavigationManager* nav = web_state->GetNavigationManager();
  if (nav && url.is_valid()) {
    nav->LoadURLWithParams(web::NavigationManager::WebLoadParams(url));
  }
  LOG(INFO) << "deskbrowser-jetsam: restored tab " << url;
}

class LiveTabCapController : public WebStateListObserver {
 public:
  static LiveTabCapController* GetInstance() {
    static LiveTabCapController* instance = new LiveTabCapController();
    return instance;
  }

  void Start() { AttachToLoadedBrowsers(); }

  void Enforce() {
    AttachToLoadedBrowsers();
    struct Candidate {
      raw_ptr<web::WebState> web_state;
      base::Time last_active;
    };
    std::vector<Candidate> live;
    int active_live = 0;

    for (WebStateList* list : observed_) {
      if (!list) {
        continue;
      }
      web::WebState* active = list->GetActiveWebState();
      for (int i = 0; i < list->count(); ++i) {
        web::WebState* ws = list->GetWebStateAt(i);
        if (!ws || ws->IsBeingDestroyed() || IsDiscarded(ws) ||
            !ws->IsRealized()) {
          continue;
        }
        if (ws == active) {
          ++active_live;
          continue;
        }
        live.push_back({ws, ws->GetLastActiveTime()});
      }
    }

    const int allowed_background = std::max(0, kMaxLiveTabs - active_live);
    if (static_cast<int>(live.size()) <= allowed_background) {
      return;
    }
    std::sort(live.begin(), live.end(),
              [](const Candidate& a, const Candidate& b) {
                return a.last_active < b.last_active;
              });
    const int drop = static_cast<int>(live.size()) - allowed_background;
    for (int i = 0; i < drop; ++i) {
      DiscardTab(live[i].web_state);
    }
  }

  void WebStateListDidChange(WebStateList* web_state_list,
                             const WebStateListChange& change,
                             const WebStateListStatus& status) override {
    if (status.active_web_state_change() && status.new_active_web_state) {
      RestoreIfDiscarded(status.new_active_web_state);
    }
    // Do not mutate during the observer callback; enforce on the next turn.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&LiveTabCapController::Enforce,
                                  weak_factory_.GetWeakPtr()));
  }

  void WebStateListDestroyed(WebStateList* web_state_list) override {
    observed_.erase(web_state_list);
  }

 private:
  LiveTabCapController() = default;

  void AttachToLoadedBrowsers() {
    ApplicationContext* app = GetApplicationContext();
    if (!app) {
      return;
    }
    ProfileManagerIOS* profiles = app->GetProfileManager();
    if (!profiles) {
      return;
    }
    for (ProfileIOS* profile : profiles->GetLoadedProfiles()) {
      if (!profile) {
        continue;
      }
      BrowserList* browsers = BrowserListFactory::GetForProfile(profile);
      if (!browsers) {
        continue;
      }
      // Avoid kAll: inactive browsers may have unrealized WebStates
      // without tab helpers (crbug.com/432020830).
      for (Browser* browser :
           browsers->BrowsersOfType(BrowserList::BrowserType::kRegularAndIncognito)) {
        if (!browser) {
          continue;
        }
        WebStateList* list = browser->GetWebStateList();
        if (!list) {
          continue;
        }
        if (observed_.insert(list).second) {
          list->AddObserver(this);
        }
      }
    }
  }

  std::set<raw_ptr<WebStateList>> observed_;
  base::WeakPtrFactory<LiveTabCapController> weak_factory_{this};
};

}  // namespace

void DeskBrowserStartLiveTabCap() {
  LiveTabCapController::GetInstance()->Start();
}

void DeskBrowserEnforceLiveTabCap() {
  LiveTabCapController::GetInstance()->Enforce();
}
