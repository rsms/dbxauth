#import "AppDelegate.h"
#import "dbxauth.h"

static const dbxauth::App dbx{"awoo8v8em3nvl8q"};

@interface AppDelegate ()
@property (assign) IBOutlet NSWindow* window;
@property (assign) IBOutlet NSTableView* accountsTableView;
@property NSInteger selectedTableRow;
@end


@implementation AppDelegate {
  dbxauth::AccountList _accounts;
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  // Find any linked Dropbox accounts. This essentially queries the keychain, and
  // the first time we launch the app we probably want to use the
  // "linked_accounts_sync" instead of "linked_accounts" here, to have the app wait
  // until we know if there's any existing linked account.
  // But this app doesn't *require* an account, so for the sake of simplicity, we
  // use the async "linked_accounts" instead.
  [self updateAccountsTable];

  self.accountsTableView.delegate = self;
  self.accountsTableView.dataSource = self;
}


- (void)updateAccountsTable {
  dbx.linked_accounts([=](dbxauth::AccountList accounts) {
    _accounts = std::move(accounts);
    NSLog(@"accounts:");
    for (auto& account : _accounts) {
      NSLog(@"  %s => %s", account.uid.c_str(), account.access_token.c_str());
    }
    [self.accountsTableView reloadData];
  });
}


- (IBAction)addAccount:(id)sender {
  dbx.link_account([=](dbxauth::Account account) {
    if (!account.is_valid()) {
      [NSAlert alertWithError:[NSError errorWithDomain:@"dbxauth" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Failed to link account"}]];
      return;
    }
    [self updateAccountsTable];
  });
}


- (IBAction)removeSelectedAccount:(id)sender {
  NSLog(@"removeSelectedAccount:");
  if (self.selectedTableRow != 0) {
    auto& account = _accounts[self.selectedTableRow-1];
    dbx.unlink_account(account.uid, nullptr);
  }
}


#pragma mark - NSTableViewDataSource


- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return _accounts.size();
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView
   viewForTableColumn:(NSTableColumn*)tableColumn
                  row:(NSInteger)row {
  
  NSTableCellView* view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  
  auto& account = _accounts[row];
  
  if ([tableColumn.identifier isEqualToString:@"uid"]) {
    view.textField.stringValue = [NSString stringWithUTF8String:account.uid.c_str()];
  } else {
    view.textField.stringValue = [NSString stringWithUTF8String:account.access_token.c_str()];
  }
  
  return view;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  self.selectedTableRow = self.accountsTableView.selectedRow+1;
}


@end
