#include "dbxauth.h"
#include "json11.hh"
using json11::Json;

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


static NSMutableDictionary* create_keychain_search_dict(NSString* identifier) {
  NSData *ident = [identifier dataUsingEncoding:NSUTF8StringEncoding];
  return [NSMutableDictionary dictionaryWithDictionary:
          @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
          //(__bridge id)kSecAttrGeneric: ident,
          (__bridge id)kSecAttrAccount: ident,
          (__bridge id)kSecAttrService: [NSBundle mainBundle].bundleIdentifier }];
}

static NSData* keychain_get_data(NSString* key) {
  NSMutableDictionary *q = create_keychain_search_dict(key);
  q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
  q[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
  CFTypeRef result = NULL;
  SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
  return result == NULL ? nil : (__bridge_transfer NSData*)result;
}

static BOOL keychain_add_data(NSString* key, NSData* value) {
  NSMutableDictionary *q = create_keychain_search_dict(key);
  q[(__bridge id)kSecValueData] = value;
  return (SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess);
}

static BOOL keychain_update_data(NSString* key, NSData* value) {
  NSMutableDictionary *q = create_keychain_search_dict(key);
  q[(__bridge id)kSecValueData] = value;
  return (SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)q) == errSecSuccess);
}

//static BOOL keychain_remove(NSString* key) {
//  NSMutableDictionary *q = create_keychain_search_dict(key);
//  return (SecItemDelete((__bridge CFDictionaryRef)q) == errSecSuccess);
//}

static BOOL keychain_set_data(NSString* key, NSData* value) {
  if (!keychain_add_data(key, value)) {
    return keychain_update_data(key, value);
  }
  return YES;
}


static Json keychain_get_dbx_accounts() {
  using json11::Json;
  NSData* data = keychain_get_data(@"dbx_accounts");
  if (!data) {
    return Json{};
  }
  std::string parse_error;
  return Json::parse(std::string{(const char*)data.bytes, data.length}, parse_error);
}

static bool keychain_set_dbx_accounts(Json accounts) {
  const std::string s{Json{accounts}.dump()};
  return keychain_set_data(@"dbx_accounts", [NSData dataWithBytes:s.data() length:s.size()]);
}

// -------------------------------------------------------------------------------------------------------------

static void HandleAuthReply(const std::string& uri,
                            std::function<void(dbxauth::Account)> callback)
{

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    dbxauth::Account account;
    if (dbxauth::parse_oauth2_reply(account, uri)) {
      // captures: self, account
      auto json = keychain_get_dbx_accounts();
      Json::array accounts;
      if (json.is_array()) {
        accounts = json.array_items();
      };
      accounts.emplace_back(Json::object{
        {"access_token", account.access_token},
        {"uid", account.uid}
      });
      if (!keychain_set_dbx_accounts(accounts)) {
        account.uid.clear();
        account.access_token.clear();
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      callback(account);
    });
  });
}


// -------------------------------------------------------------------------------------------------------------

@interface _DBXAuthWebViewDelegate : NSObject
@property NSProgressIndicator* progressIndicator;
@end
@implementation _DBXAuthWebViewDelegate {
@public
  std::function<void(NSError*,NSURL*)> callback;
}
#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
  NSLog(@"%@  frame.provisionalDataSource.request.URL=%@", NSStringFromSelector(_cmd), frame.provisionalDataSource.request.URL);
  [self.progressIndicator startAnimation:nil];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
  NSLog(@"%@", NSStringFromSelector(_cmd));
  [self.progressIndicator stopAnimation:nil];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
  NSLog(@"%@", NSStringFromSelector(_cmd));
  [self.progressIndicator stopAnimation:nil];
  self->callback(error, nil);
  // FIXME TODO: Reload? Display error message?
}

//- (void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)URL delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame {
//  NSLog(@"%@ %@", NSStringFromSelector(_cmd), URL);
//}

#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
          frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener {
  NSLog(@"%@ actionInformation=%@  request=%@", NSStringFromSelector(_cmd), actionInformation, request);
  
  if ([request.URL.host isEqualToString:@"localhost"]) {
    [listener ignore];
    self->callback(nil, request.URL);
  } else {
    [listener use];
  }
}

@end


// -------------------------------------------------------------------------------------------------------------


/*static NSMutableArray* g_openURLHandlers = nil;

@interface _dbxauthOpenURLHandler : NSObject
@end
@implementation _dbxauthOpenURLHandler {
@public
  std::function<void(dbxauth::Account)> callback;
}
- (void)handleOpenURLAEEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent {
  NSString *urlAsString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
  
  if (!HandleAuthReply(urlAsString.UTF8String, self->callback)) {
    self->callback(dbxauth::Account{});
  }
  
  [g_openURLHandlers removeObject:self];
}
@end*/

// -------------------------------------------------------------------------------------------------------------

namespace dbxauth {


AccountList App::linked_accounts_sync() const {
  auto json = keychain_get_dbx_accounts();
  AccountList accounts;
  if (json.is_array()) {
    auto& array_items = json.array_items();
    accounts.reserve(array_items.size());
    for (auto& entry : array_items) {
      if (entry.is_object()) {
        accounts.emplace_back(Account{entry["access_token"].string_value(), entry["uid"].string_value()});
      }
    }
  }
  return std::move(accounts);
}


void App::linked_accounts(std::function<void(AccountList)> cont) const {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    AccountList accounts = linked_accounts_sync();
    dispatch_async(dispatch_get_main_queue(), ^{
      cont(std::move(accounts));
    });
  });
}
  
  
void App::link_account(std::function<void(Account)> cb) const {
  link_account(system_auth_activation_uri(), cb);
}


// Here be dragons! Terrible hack, but it works for now...
static NSWindow* gAuthWebViewWindow = nil;
static _DBXAuthWebViewDelegate* gAuthWebViewDelegate = nil;


void App::link_account(const std::string& app_uri_base, std::function<void(Account)> cont) const {
  
  auto frame = NSMakeRect(0, 0, 500, 500);
  auto* webView = [[WebView alloc] initWithFrame:frame];
  webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  auto* window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO screen:[NSScreen mainScreen]];
  auto* contentView = (NSView*)window.contentView;
  [contentView addSubview:webView];
  
  // enable local storage
  WebPreferences* prefs = [WebPreferences standardPreferences];
  if ([prefs respondsToSelector:@selector(setLocalStorageEnabled:)]) {
    NSLog(@"localstorage set");
    [prefs performSelector:@selector(setLocalStorageEnabled:) withObject:[NSNumber numberWithBool:YES]];
  }
  prefs.autosaves = YES;
  webView.preferences = prefs;
  
  // web view delegate
  auto* webViewDelegate = [_DBXAuthWebViewDelegate new];
  webView.frameLoadDelegate = webViewDelegate;
  webView.policyDelegate = webViewDelegate;
  webViewDelegate->callback = [=](NSError* err, NSURL* replyURL) {
    if (err) {
      // Failure TODO FIXME
      NSLog(@"Dropbox Auth failure: %@", err);
      cont(dbxauth::Account{});
    } else {
      HandleAuthReply(replyURL.description.UTF8String, cont);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      webView.frameLoadDelegate = nil;
      webView.policyDelegate = nil;
      gAuthWebViewWindow.contentView = [NSView new];
      gAuthWebViewWindow.releasedWhenClosed = NO;
      [gAuthWebViewWindow close];
      gAuthWebViewWindow = nil;
      //gAuthWebViewDelegate = nil;
    });
  };
  
  // progress indicator
  NSRect progressIndicatorFrame = NSMakeRect(0, 0, 32, 32);
  progressIndicatorFrame.origin.x = (frame.size.width-progressIndicatorFrame.size.width)/2;
  progressIndicatorFrame.origin.y = (frame.size.height-progressIndicatorFrame.size.height)/2;
  webViewDelegate.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:progressIndicatorFrame];
  webViewDelegate.progressIndicator.indeterminate = YES;
  webViewDelegate.progressIndicator.bezeled = YES;
  webViewDelegate.progressIndicator.controlSize = NSRegularControlSize;
  webViewDelegate.progressIndicator.style = NSProgressIndicatorSpinningStyle;
  webViewDelegate.progressIndicator.displayedWhenStopped = NO;
  [contentView addSubview:webViewDelegate.progressIndicator];

  // Load URL
  std::string url = dbxauth::oauth2_url(this->key, "http://localhost");
  auto* oauthDialogURL = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
  auto* req = [[NSMutableURLRequest alloc] initWithURL:oauthDialogURL];
  [webView.mainFrame loadRequest:req];
  
  [window center];
  [window makeKeyAndOrderFront:nil];
  
  gAuthWebViewWindow = window;
  gAuthWebViewDelegate = webViewDelegate;

  /*static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{
    g_openURLHandlers = [NSMutableArray new];
  });

  _dbxauthOpenURLHandler* handler = [_dbxauthOpenURLHandler new];
  handler->callback = cont;
  [g_openURLHandlers addObject:handler];
  // TODO: Move handler ref kept by g_openURLHandlers into `this` App instance

  [[NSAppleEventManager sharedAppleEventManager] setEventHandler:handler
                                                     andSelector:@selector(handleOpenURLAEEvent:withReplyEvent:)
                                                   forEventClass:kInternetEventClass
                                                      andEventID:kAEGetURL];
  
   std::string url = dbxauth::oauth2_url(this->key, app_uri_base);
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]]];*/
}


void App::unlink_account(const std::string& account_uid, std::function<void(bool)> cont) const {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    auto json = keychain_get_dbx_accounts();
    bool did_remove = false;
    if (json.is_array()) {
      Json::array accounts;
      for (auto obj : json.array_items()) {
        if (obj.is_object() && obj["uid"] == account_uid) {
          did_remove = true;
        } else {
          accounts.push_back(obj);
        }
      }
      if (did_remove) {
        keychain_set_dbx_accounts(accounts);
      }
    }
    if (cont != nullptr) {
      dispatch_async(dispatch_get_main_queue(), ^{
        cont(did_remove);
      });
    }
  });
}


} // namespace
