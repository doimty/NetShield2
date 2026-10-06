#import "../Shared/NSLocalization.h"
#import "NSDashboard+Internal.h"
#import "../Shared/NSActivity.h"
#import "NSHostsImportController.h"

@implementation NSDashboard (Table)
- (BOOL)showsSystemRules {
    return self.policy && ![self.policy.document[@"allowAppleSystemProcesses"] boolValue];
}
- (NSArray<NSString *> *)identitiesForSection:(NSInteger)section {
    return section == NSDashboardSectionSystemRules ? self.systemIdentities : self.identities;
}
- (id)rowKey:(NSIndexPath *)path {
    if (path.section == NSDashboardSectionGlobalRules && self.globalRuleKeys.count) {
        return self.globalRuleKeys[path.row];
    }
    if (path.section == NSDashboardSectionRequests && [self.monitor[@"requests"] count]) {
        return self.monitor[@"requests"][path.row][@"token"];
    }
    if ((path.section == NSDashboardSectionRules || path.section == NSDashboardSectionSystemRules) &&
        [self identitiesForSection:path.section].count) {
        return [self identitiesForSection:path.section][path.row];
    }
    if (path.section == NSDashboardSectionActivity && self.activityGroups.count) {
        return self.activityGroups[path.row][@"groupKey"];
    }
    return @(path.row);
}
- (id)heightKey:(NSIndexPath *)path {
    return @[
        @(path.section), [self rowKey:path],
        path.section == NSDashboardSectionActivity && self.activityGroups.count
            ? self.activityGroups[path.row]
            : @{},
        @(self.tableView.bounds.size.width), self.traitCollection.preferredContentSizeCategory
    ];
}
- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)path {
    NSNumber *height = self.rowHeights[[self heightKey:path]];
    return height ? height.doubleValue : 64;
}
- (void)tableView:(UITableView *)tableView
      willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)path {
    if (self.rowHeights.count > 5000) {
        [self.rowHeights removeAllObjects];
    }
    self.rowHeights[[self heightKey:path]] = @(cell.bounds.size.height);
}
- (void)refreshTableKeepingPosition {
    NSArray *signature = @[
        self.policy.document ?: @{}, self.monitor[@"requests"] ?: @[], self.monitor[@"events"] ?: @[],
        self.monitor[@"policyError"] ?: @"", self.monitor[@"dnsIssue"] ?: @"",
        self.monitor[@"notificationDeliveryIssue"] ?: @"", @([self hasFreshMonitor]), @(self.loaded),
        @(self.busy), @(NEFilterManager.sharedManager.enabled),
        @(NEFilterManager.sharedManager.providerConfiguration.filterSockets), self.message ?: @"",
        self.notificationStatus ?: @"", self.policyReadError ?: @"", self.monitor[@"overflowCount"] ?: @0,
        self.monitor[@"evictedRequestCount"] ?: @0
    ];
    if ([signature isEqual:self.displaySignature]) {
        return;
    }
    self.displaySignature = signature;
    __block CGPoint offset = self.tableView.contentOffset;
    BOOL atTop = offset.y <= -self.tableView.adjustedContentInset.top + 1;
    NSMutableArray *anchors = [NSMutableArray new];
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        if ((NSUInteger)path.section < self.displayedRows.count &&
            (NSUInteger)path.row < [self.displayedRows[path.section] count]) {
            [anchors addObject:@[
                @(path.section), self.displayedRows[path.section][path.row],
                @([self.tableView rectForRowAtIndexPath:path].origin.y - offset.y)
            ]];
        }
    }
    self.activityGroups = NSGroupedActivity(self.monitor[@"events"] ?: @[]);
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
        NSMutableArray *keys = [NSMutableArray new];
        for (NSInteger row = 0; row < [self tableView:self.tableView numberOfRowsInSection:section]; row++) {
            [keys addObject:[self rowKey:[NSIndexPath indexPathForRow:row inSection:section]]];
        }
        [rows addObject:keys];
    }
    self.displayedRows = rows;
    [UIView performWithoutAnimation:^{
        [self.tableView reloadData];
        [self.tableView layoutIfNeeded];
        if (!atTop) {
            for (NSArray *anchor in anchors) {
                NSInteger section = [anchor[0] integerValue];
                NSUInteger row = [rows[section] indexOfObject:anchor[1]];
                if (row == NSNotFound) {
                    continue;
                }
                offset.y = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row
                                                                                    inSection:section]]
                               .origin.y -
                           [anchor[2] doubleValue];
                break;
            }
        }
        CGFloat minimum = -self.tableView.adjustedContentInset.top;
        CGFloat maximum = MAX(minimum, self.tableView.contentSize.height - self.tableView.bounds.size.height +
                                           self.tableView.adjustedContentInset.bottom);
        [self.tableView
            setContentOffset:CGPointMake(offset.x, atTop ? minimum : MIN(maximum, MAX(minimum, offset.y)))
                    animated:NO];
    }];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return NSDashboardSectionCount;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == NSDashboardSectionFirewall) {
        return 6;
    }
    if (section == NSDashboardSectionRequests) {
        return MAX((NSUInteger)1, [self.monitor[@"requests"] count]);
    }
    if (section == NSDashboardSectionRules) {
        return MAX((NSUInteger)1, self.identities.count);
    }
    if (section == NSDashboardSectionSystemRules) {
        return [self showsSystemRules] ? MAX((NSUInteger)1, self.systemIdentities.count) : 0;
    }
    if (section == NSDashboardSectionNotifications) {
        return 2;
    }
    if (section == NSDashboardSectionGlobalRules) {
        return MAX((NSUInteger)1, self.globalRuleKeys.count);
    }
    if (section == NSDashboardSectionAdvanced) {
        return 7;
    }
    if (section == NSDashboardSectionSupport) {
        return 2;
    }
    return MAX((NSUInteger)1, self.activityGroups.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == NSDashboardSectionSystemRules && ![self showsSystemRules]) {
        return nil;
    }
    return @[
        NSL(@"Firewall"), NSL(@"Waiting for your decision"), NSL(@"Notifications"), NSL(@"Advanced Settings"),
        NSL(@"Support"), NSL(@"Global rules"), NSL(@"App Rules"), NSL(@"System Rules"),
        NSL(@"Recent activity")
    ][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == NSDashboardSectionSystemRules) {
        return [self showsSystemRules] ? NSL(@"Tap a system identity to change its rule.") : nil;
    }
    if (section == NSDashboardSectionGlobalRules) {
        return NSL(@"Overrides app rules and the iOS system traffic allowance.");
    }
    if (section == NSDashboardSectionFirewall) {
        return NSL(@"Rules are saved when firewall is turned off.");
    }
    if (section == NSDashboardSectionRequests) {
        return [NSString stringWithFormat:NSL(@"The latest %d expired requests stay available. During this "
                                              @"filter session: %@ connections "
                                              @"rejected at queue capacity; %@ older requests removed. "),
                                          NSMaximumRequestHistory, self.monitor[@"overflowCount"] ?: @0,
                                          self.monitor[@"evictedRequestCount"] ?: @0];
    }
    if (section == NSDashboardSectionRules) {
        return NSL(@"Tap an app identity to change its rule.");
    }
    if (section == NSDashboardSectionNotifications) {
        return NSL(@"Tap Notification Settings to customize.");
    }
    if (section == NSDashboardSectionActivity) {
        return NSL(@"Up to 300 recorded events");
    }
    if (section == NSDashboardSectionSupport) {
        return NSL(@"Developed by EolnMsuk.");
    }
    return @"NetShield2 2.2.8-1+hosts2 / iOS 15-18.";
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == NSDashboardSectionSystemRules && ![self showsSystemRules]
               ? CGFLOAT_MIN
               : UITableViewAutomaticDimension;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == NSDashboardSectionSystemRules && ![self showsSystemRules]
               ? CGFLOAT_MIN
               : UITableViewAutomaticDimension;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cached = nil;
    if (path.section == NSDashboardSectionFirewall) {
        if (path.row == 0) {
            cached = self.firewallCell;
        } else if (path.row == 2) {
            cached = self.appleCell;
        }
    }
    if (cached) {
        UISwitch *toggle = (UISwitch *)cached.accessoryView;
        BOOL on = path.row == 0 ? self.loaded && NEFilterManager.sharedManager.enabled
                                : [self.policy.document[@"allowAppleSystemProcesses"] boolValue];
        BOOL enabled = (path.row == 0 ? self.loaded : self.policy != nil) && !self.busy;
        if (toggle.on != on) {
            [toggle setOn:on animated:NO];
        }
        if (toggle.enabled != enabled) {
            toggle.enabled = enabled;
        }
        return cached;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (path.section == NSDashboardSectionFirewall && path.row == 0) {
        cell.textLabel.text = NSL(@"Firewall");
        cell.detailTextLabel.text = NSL(@"Control internet access for your apps");
        cell.imageView.image = [UIImage systemImageNamed:@"shield.lefthalf.filled"];
        UISwitch *toggle = [UISwitch new];
        if (self.loaded && NEFilterManager.sharedManager.enabled) {
            [toggle setOn:YES animated:NO];
        }
        toggle.enabled = self.loaded && !self.busy;
        toggle.accessibilityLabel = NSL(@"Firewall");
        [toggle addTarget:self
                      action:@selector(firewallChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == NSDashboardSectionFirewall && path.row == 3) {
        BOOL enabled = self.loaded && NEFilterManager.sharedManager.enabled;
        BOOL healthy =
            enabled && self.policy && [self hasFreshMonitor] && ![self.monitor[@"policyError"] length];
        if (self.busy) {
            cell.textLabel.text = NSL(@"Updating...");
        } else if (!self.loaded) {
            cell.textLabel.text = NSL(@"Unable to read firewall status");
        } else if (!enabled) {
            cell.textLabel.text = NSL(@"Off");
        } else {
            cell.textLabel.text = healthy ? NSL(@"Active") : NSL(@"Needs attention");
        }
        cell.textLabel.textColor = healthy ? UIColor.systemGreenColor : UIColor.labelColor;
        NSString *detail =
            NSL(@"The filter has not reported a healthy status. Turn Firewall off and on if this continues.");
        if (!enabled) {
            detail = NSL(@"Turn on Firewall to apply your rules.");
        } else if (healthy) {
            detail = NEFilterManager.sharedManager.providerConfiguration.filterSockets
                         ? NSL(@"Browser and socket filtering active.")
                         : NSL(@"Browser filtering only. Enable Filter System Sockets below Firewall for "
                               @"other app connections.");
        }
        if (enabled && NEFilterManager.sharedManager.providerConfiguration.filterSockets !=
                           [self.policy.document[@"filterSockets"] boolValue]) {
            detail =
                [detail stringByAppendingString:
                            NSL(@" Pending: toggle Firewall off and on to apply the saved socket setting.")];
        }
        if ([self.monitor[@"policyError"] length]) {
            detail = NSL(self.monitor[@"policyError"]);
        }
        if ([self.monitor[@"dnsIssue"] length]) {
            detail = [detail stringByAppendingFormat:@"\n%@", NSL(self.monitor[@"dnsIssue"])];
        }
        if (self.policyReadError.length) {
            detail = self.policyReadError;
        }
        cell.detailTextLabel.text =
            [self.message length] ? [NSString stringWithFormat:@"%@\n%@", detail, self.message] : detail;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == NSDashboardSectionFirewall && path.row == 2) {
        cell.textLabel.text = NSL(@"Allow all iOS system traffic");
        cell.detailTextLabel.text = NSL(@"Allow Apple identities unless a global rule matches");
        UISwitch *toggle = [UISwitch new];
        if ([self.policy.document[@"allowAppleSystemProcesses"] boolValue]) {
            [toggle setOn:YES animated:NO];
        }
        toggle.enabled = self.policy != nil && !self.busy;
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self
                      action:@selector(appleSystemProcessesChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == NSDashboardSectionFirewall && path.row == 1) {
        cell.textLabel.text = NSL(@"Filter System Sockets");
        cell.detailTextLabel.text =
            NSL(@"Required to filter all app network. Only disable if an app crashes on launch");
        UISwitch *toggle = [UISwitch new];
        toggle.on = [self.policy.document[@"filterSockets"] boolValue];
        toggle.enabled = self.policy != nil && self.loaded && !self.busy;
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self
                      action:@selector(socketFilteringChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == NSDashboardSectionFirewall) {
        cell.textLabel.text = path.row == 5 ? NSL(@"Default Rule") : NSL(@"Unidentified");
        cell.detailTextLabel.text =
            self.policy ? [self ruleTitle:self.policy.document[path.row == 5 ? @"default" : @"unattributed"]]
                        : NSL(@"Policy unavailable");
        if (!self.policy) {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    } else if (path.section == NSDashboardSectionRequests) {
        NSArray *requests = self.monitor[@"requests"];
        if (!requests.count) {
            cell.textLabel.text = NSL(@"No apps waiting");
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            NSDictionary *request = requests[path.row];
            cell.textLabel.text = request[@"identity"];
            cell.detailTextLabel.text = [request[@"expired"] boolValue]
                                            ? NSL(@"Blocked while waiting. Tap to decide.")
                                            : NSL(@"Tap to allow or keep blocking");
            cell.detailTextLabel.text = [cell.detailTextLabel.text
                stringByAppendingFormat:NSL(@"\nFirst requested peer: %@"),
                                        NSDestinationSummary(request[@"destination"])];
        }
    } else if (path.section == NSDashboardSectionGlobalRules) {
        if (!self.globalRuleKeys.count) {
            cell.textLabel.text = NSL(@"No global rules");
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            NSString *key = self.globalRuleKeys[path.row];
            NSString *rule = self.policy.document[@"globalRules"][key];
            UIColor *color = [rule isEqual:@"allow"] ? UIColor.systemGreenColor
                             : [rule isEqual:@"block"] || [rule isEqual:@"block-outbound"]
                                 ? UIColor.systemRedColor
                             : [rule isEqual:@"block-inbound"] ? UIColor.systemOrangeColor
                                                               : nil;
            if (color) {
                cell.backgroundColor = [color colorWithAlphaComponent:0.14];
            }
            cell.textLabel.text = [self globalRuleTitle:key];
            cell.detailTextLabel.text = [self ruleTitle:rule];
        }
    } else if (path.section == NSDashboardSectionRules || path.section == NSDashboardSectionSystemRules) {
        NSArray<NSString *> *identities = [self identitiesForSection:path.section];
        if (!identities.count) {
            cell.textLabel.text = path.section == NSDashboardSectionSystemRules
                                      ? NSL(@"System processes appear here when they connect")
                                      : NSL(@"Apps appear here when they connect");
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            NSString *identity = identities[path.row];
            NSString *rule = self.policy.document[@"rules"][identity];
            UIColor *color = [rule isEqual:@"allow"] ? UIColor.systemGreenColor
                             : [rule isEqual:@"block"] || [rule isEqual:@"block-outbound"]
                                 ? UIColor.systemRedColor
                             : [rule isEqual:@"block-inbound"] ? UIColor.systemOrangeColor
                                                               : nil;
            if (color) {
                cell.backgroundColor = [color colorWithAlphaComponent:0.14];
            }
            cell.textLabel.text = identity;
            cell.detailTextLabel.text =
                [self.policy automaticallyAllowsIdentity:identity]
                    ? [NSString
                          stringWithFormat:
                              NSL(@"Allowed by iOS setting unless a global rule matches. Saved rule: %@"),
                              [self ruleTitle:self.policy.document[@"rules"][identity]]]
                    : [self ruleTitle:self.policy.document[@"rules"][identity]];
            NSDictionary *destination = self.policy.document[@"ruleDestinations"][identity];
            if (destination) {
                cell.detailTextLabel.text = [cell.detailTextLabel.text
                    stringByAppendingFormat:NSL(@"\nFirst requested peer: %@ (rule applies to the app)"),
                                            NSDestinationSummary(destination)];
            }
        }
    } else if (path.section == NSDashboardSectionNotifications) {
        cell.textLabel.text =
            path.row == 0 ? NSL(@"Notification Settings") : NSL(@"Banners & Do Not Disturb");
        cell.detailTextLabel.text =
            path.row == 0 ? self.notificationStatus : NSL(@"How to answer while using another app");
        if (path.row == 0 && [self hasFreshMonitor] && [self.monitor[@"notificationDeliveryIssue"] length]) {
            cell.detailTextLabel.text = NSL(self.monitor[@"notificationDeliveryIssue"]);
        }
    } else if (path.section == NSDashboardSectionActivity) {
        NSArray *events = self.activityGroups;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!events.count) {
            cell.textLabel.text = NSL(@"No activity yet");
        } else {
            NSDictionary *event = events[path.row];
            BOOL allowed = [event[@"action"] isEqual:@"allow"];
            BOOL blocked = [event[@"action"] isEqual:@"block"];
            NSString *action = allowed ? NSL(@"Allowed") : blocked ? NSL(@"Blocked") : NSL(@"Connection");
            UIColor *color = allowed ? UIColor.systemGreenColor : blocked ? UIColor.systemRedColor : nil;
            if (color) {
                cell.backgroundColor = [color colorWithAlphaComponent:0.14];
            }
            if ([event[@"identity"] length]) {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            cell.textLabel.text = [NSString
                stringWithFormat:@"%@ / %@", action,
                                 [event[@"identity"] length] ? event[@"identity"] : NSL(@"Unidentified app")];
            NSString *time = [NSDateFormatter localizedStringFromDate:event[@"time"]
                                                            dateStyle:NSDateFormatterShortStyle
                                                            timeStyle:NSDateFormatterShortStyle];
            NSString *direction = @{
                @"inbound" : NSL(@"Incoming"),
                @"outbound" : NSL(@"Outgoing"),
                @"unknown" : NSL(@"Unknown direction")
            }[event[@"direction"]]
                                      ?: event[@"direction"];
            cell.detailTextLabel.text =
                [NSString stringWithFormat:NSL(@"%@ / %@\nConnections: %@\nReceived %.1f MB / Sent %.1f MB"),
                                           time, direction, event[@"connections"],
                                           [event[@"bytesIn"] unsignedLongLongValue] / 1000000.0,
                                           [event[@"bytesOut"] unsignedLongLongValue] / 1000000.0];
            cell.detailTextLabel.text = [cell.detailTextLabel.text
                stringByAppendingFormat:@"\n%@", NSDestinationSummary(event[@"destination"])];
        }
    } else if (path.section == NSDashboardSectionSupport) {
        cell.textLabel.text = path.row == 0 ? NSL(@"GitHub Link") : NSL(@"Support Developer");
        cell.detailTextLabel.text =
            path.row == 0 ? NSL(@"Source code, releases and issues") : NSL(@"Choose Venmo or Bitcoin");
        cell.textLabel.textColor = UIColor.systemBlueColor;
    } else {
        cell.textLabel.text = @[
            NSL(@"Add a rule by app identity"), NSL(@"Add a rule by IP / Domain"),
            NSL(@"Add a rule by port number"), NSL(@"Export Rules and Recent Activity"),
            NSL(@"Import Hosts Blocklist"), NSL(@"Reset Rules & History"), NSL(@"Reset ALL Settings")
        ][path.row];
        cell.detailTextLabel.text = @[
            NSL(@"For an exact identity supplied by iOS"), NSL(@"For an IP or domain across all processes"),
            NSL(@"For a port across all processes"), NSL(@"Share rules and recent activity as a JSON file"),
            NSL(@"Paste or choose a Hosts file; preview before adding blocking domains"),
            NSL(@"Reset rules and history only"),
            NSL(@"Removes all rules, permissions and filters. Runs automatically during uninstall.")
        ][path.row];
        if (path.row == 3 || path.row == 4) {
            cell.textLabel.textColor = UIColor.systemBlueColor;
        } else if (path.row > 4) {
            cell.textLabel.textColor = UIColor.systemRedColor;
        }
    }
    if (path.section == NSDashboardSectionFirewall && path.row == 0) {
        self.firewallCell = cell;
    }
    if (path.section == NSDashboardSectionFirewall && path.row == 2) {
        self.appleCell = cell;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.busy) {
        return;
    }
    if (path.section == NSDashboardSectionFirewall && path.row == 5) {
        [self chooseActionForIdentity:nil defaultKey:@"default"];
    } else if (path.section == NSDashboardSectionRequests && [self.monitor[@"requests"] count]) {
        [self presentRequest:self.monitor[@"requests"][path.row]];
    } else if (path.section == NSDashboardSectionGlobalRules && self.globalRuleKeys.count) {
        [self chooseGlobalRule:self.globalRuleKeys[path.row]];
    } else if ((path.section == NSDashboardSectionRules || path.section == NSDashboardSectionSystemRules) &&
               [self identitiesForSection:path.section].count) {
        [self chooseActionForIdentity:[self identitiesForSection:path.section][path.row] defaultKey:nil];
    } else if (path.section == NSDashboardSectionActivity && self.activityGroups.count) {
        NSString *identity = self.activityGroups[path.row][@"identity"];
        if (identity.length) {
            [self chooseActionForIdentity:identity defaultKey:nil];
        }
    } else if (path.section == NSDashboardSectionNotifications) {
        if (path.row == 0) {
            [self requestNotifications];
        } else {
            [self showNotificationHelp];
        }
    } else if (path.section == NSDashboardSectionFirewall && path.row == 4) {
        [self chooseActionForIdentity:nil defaultKey:@"unattributed"];
    } else if (path.section == NSDashboardSectionSupport) {
        if (path.row == 0) {
            [self openSupportURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/NetShield2/"]];
        } else {
            [self supportDeveloper];
        }
    } else if (path.section == NSDashboardSectionAdvanced) {
        if (path.row == 0) {
            [self addIdentity];
        } else if (path.row == 1 || path.row == 2) {
            [self addGlobalRuleByPort:path.row == 2];
        } else if (path.row == 3) {
            [self exportRulesAndRecentActivityFromRow:path];
        } else if (path.row == 4) {
            if (!self.policy) {
                return;
            }
            NSHostsImportController *importer = [NSHostsImportController new];
            __weak typeof(self) weakSelf = self;
            importer.didImport = ^(NSUInteger count) {
                NSDashboard *dashboard = weakSelf;
                dashboard.message =
                    [NSString stringWithFormat:NSL(@"Imported %lu Hosts blocking rules for new connections. "
                                                   @"Firewall and app defaults unchanged."),
                                               (unsigned long)count];
                [dashboard reloadMonitor];
            };
            UINavigationController *navigation =
                [[UINavigationController alloc] initWithRootViewController:importer];
            navigation.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navigation animated:YES completion:nil];
        } else if (path.row < 7) {
            BOOL reset = path.row == 5;
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:reset ? NSL(@"Reset Rules & History?") : NSL(@"Reset ALL Settings?")
                                 message:
                                     reset ? NSL(@"Deletes app and global rules, pending requests and "
                                                 @"history only. "
                                                 @"Keeps your settings and restores the firewall's previous "
                                                 @"on/off state after stopping it to reset.")
                                           : NSL(@"Removes all NetShield2 rules, permissions and history, "
                                                 @"restores default settings, and removes the system filter. "
                                                 @"Package-manager uninstall removes the filter "
                                                 @"automatically. iOS notification authorization "
                                                 @"must be managed in Settings.")
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:reset ? NSL(@"Reset rules and history")
                                                                  : NSL(@"Reset all settings")
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *action) {
                                                        self.resetAllSettings = !reset;
                                                        [self resetNetShield2];
                                                    }]];
            [alert addAction:[UIAlertAction actionWithTitle:NSL(@"Cancel")
                                                      style:UIAlertActionStyleCancel
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end
