# dbxauth

Provides Dropbox authentication, and only Dropbox authentication. Tiny footprint and easy to drop into any project.

Currently only implemented for OS X, where it will present the Dropbox OAuth 2 dialog in a modal web view, and stores account data in the OS X Keychain. 

Make sure to add "http://localhost" to OAuth 2 redirect URIs at https://www.dropbox.com/developers/apps/info/APPID

## Example `AppDelegate.mm`:

```mm
#import "AppDelegate.h"
#import "dbxauth.h"

static const dbxauth::App dbx{"DROPBOX APP KEY"};

@implementation AppDelegate {
  dbxauth::AccountList _accounts;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  // Load account information synchronously from keychain. There's an async version of this call
  // as well.
  _accounts = dbx.linked_accounts_sync();

  // If no account is linked, prompt the user to link an account
  if (_accounts.empty()) {
    dbx.link_account([=](dbxauth::Account account) {
      if (!account.is_valid()) {
        // authentication failed for some reason.
        // You might want to either force the user to auth by calling dbx.link_account again,
        // and/or display an error message.
        return;
      }
      [self isAuthenticatedWithDropbox];
    });
  });
  } else {
    [self isAuthenticatedWithDropbox];
  }
}

- (void)isAuthenticatedWithDropbox {
  // Start using accounts in _accounts
}

@end
```


## MIT license

Copyright (c) 2015 Rasmus Andersson <http://rsms.me/>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
