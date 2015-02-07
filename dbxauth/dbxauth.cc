#include "dbxauth.h"

namespace dbxauth {


std::string oauth2_url(const std::string& app_key, const std::string& reply_uri) {
  return std::string{"https://www.dropbox.com/1/oauth2/authorize?response_type=token&client_id="} +
    app_key + "&redirect_uri=" + reply_uri;
  // TODO: URI encoding of reply_uri and app_key
}
  

bool parse_oauth2_reply(Account& account, const std::string& uri) {
  // <anything>
  //   #access_token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  //   &token_type=bearer
  //   &uid=1234
  // or
  // <anything>
  //   %23access_token=XXXXXX...
  
  size_t pos = 0, pos2;
  if ((pos = uri.find_first_of('#')) == std::string::npos) {
    if ((pos = uri.find("%23")) == std::string::npos) {
      return false;
    } else {
      pos += 3; // skip past "%23"
    }
  } else {
    ++pos; // skip past the '#' char
  }
  
  account.access_token.clear();
  account.uid.clear();
  
  while (pos < uri.size()) {
    // key
    if ((pos2 = uri.find_first_of('=', pos)) == std::string::npos) {
      return false;
    }
    std::string key = uri.substr(pos, pos2-pos);
    //printf("Found key '%s'\n", key.c_str());
    pos = pos2 + 1; // + skip '=' char
    
    // value
    if ((pos2 = uri.find_first_of('&', pos)) == std::string::npos) {
      // last value
      pos2 = uri.size()-1;
    }
    
    // printf("Found value '%s'\n", uri.substr(pos, pos2-pos).c_str());
    
    if (key.compare("access_token") == 0) {
      account.access_token = uri.substr(pos, pos2-pos); // todo: sanitize data
    } else if (key.compare("uid") == 0) {
      account.uid = uri.substr(pos, pos2-pos); // todo: sanitize data
    }
    
    pos = pos2 + 1; // + skip '=' char
  }
  
  // check values
  if (account.access_token.empty() || account.uid.empty()) {
    return false;
  }
  
  return true;
}


std::string App::system_auth_activation_uri() const {
  return std::string{"db-"} + key + ":authreply";
}


} // namespace
