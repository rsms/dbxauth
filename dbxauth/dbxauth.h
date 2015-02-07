#pragma once
#ifdef __cplusplus

#include <utility>
#include <memory>
#include <string>
#include <functional>
#include <vector>

namespace dbxauth {

// Represents a specific user account
struct Account {
  std::string  access_token;  // Dropbox OAuth2 access token
  std::string  uid;           // Stable Dropbox user ID (opaque byte string)
  bool is_valid() const { return !access_token.empty(); }
};


typedef std::vector<Account> AccountList;


struct App {
  App(const std::string& key) : key{key} {}
  
  void linked_accounts(std::function<void(AccountList)>) const;
  AccountList linked_accounts_sync() const;
    // Returns a list of authenticated accounts

  void link_account(std::function<void(Account)>) const;
  void link_account(const std::string& app_uri_base, std::function<void(Account)>) const;
    // Link a new account.
  
  void unlink_account(const std::string& account_uid, std::function<void(bool did_remove)> = nullptr) const;
    // Remove an already linked account
  
  std::string system_auth_activation_uri() const;
    // Returns a string representing the app within the system. On OS X this will be an actual URI,
    // e.g. "db-appkey:authreply". This is the URI that needs to be associated with the Dropbox
    // app in https://www.dropbox.com/developers/apps/info/<appkey>.

  std::string key;
};


std::string oauth2_url(const std::string& app_key, const std::string& app_uri_base);
  // Returns a URL that should be used to present an authentication dialog to the user.
  // `app_uri_base` should be a URI that this app is registered for, and will have access_token
  // and other parameters appended to it.

bool parse_oauth2_reply(Account& account, const std::string& reply_uri);
  // Parses an oauth2 reply URI, as returned from an oauth2 roundtrip triggered by
  // requesting `oauth2_url()`. Returns false if `uri` is malformed. When successful,
  // `account` will be modified to contain the access token and uid.

} // namespace

#endif /* defined(__cplusplus) */
