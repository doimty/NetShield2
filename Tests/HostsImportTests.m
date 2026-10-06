#import <Foundation/Foundation.h>
#import "../Shared/NSHostsImport.h"
#import "../Shared/NSGlobalRule.h"
#import "../Shared/NSStore.h"
#include <stdlib.h>
#include <string.h>

static NSUInteger checks;
#define CHECK(...)                                                                                           \
    do {                                                                                                     \
        checks++;                                                                                            \
        if (!(__VA_ARGS__)) {                                                                                \
            NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #__VA_ARGS__);                                      \
            abort();                                                                                         \
        }                                                                                                    \
    } while (0)

static NSHostsImportResult *Parse(NSString *text) {
    return NSParseHostsData([text dataUsingEncoding:NSUTF8StringEncoding], NULL);
}
static NSMutableDictionary *Document(NSDictionary *rules) {
    NSMutableDictionary *document = [[NSPolicy defaultDocument] mutableCopy];
    document[@"globalRules"] = rules;
    return document;
}
static NSData *Encode(NSDictionary *document) {
    return [NSPropertyListSerialization dataWithPropertyList:document
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0
                                                       error:NULL];
}
static NSArray *Keys(NSUInteger count) {
    NSMutableArray *keys = [NSMutableArray new];
    for (NSUInteger index = 0; index < count; index++) {
        [keys addObject:[NSString stringWithFormat:@"domain:h%04lu.test", (unsigned long)index]];
    }
    return keys;
}
static void TestParsing(void) {
    NSHostsImportResult *result = Parse(@"# 注释\n0.0.0.0 Ads.Example. ads.example\n"
                                        @"127.0.0.1 localhost tracker.example\n"
                                        @":: v6.example\n::1 ip6-localhost loop.example\n"
                                        @"192.0.2.1 redirect.example\n");
    CHECK(result != nil);
    CHECK([result.domainKeys isEqual:@[
        @"domain:ads.example", @"domain:loop.example", @"domain:tracker.example", @"domain:v6.example"
    ]]);
    CHECK(result.duplicateCount == 1);
    CHECK(result.stats.acceptedNames == 5);
    CHECK(result.stats.localNames == 2);
    CHECK(result.stats.redirectLines == 1);
    CHECK(result.stats.ignoredLines == 1);
    CHECK(result.stats.lines == 6);
    result = Parse(@"");
    CHECK(result != nil && result.domainKeys.count == 0);
    result = Parse(@"192.0.2.1 redirect.test\n");
    CHECK(result != nil && result.domainKeys.count == 0);
    CHECK([Parse(@"0.0.0.0 www.ads.test ads.test\n").domainKeys
        isEqual:@[ @"domain:ads.test", @"domain:www.ads.test" ]]);
    CHECK(Parse(@"0.0.0.0 -bad.test bad_.test\n").stats.invalidNames == 2);
    const unsigned char invalid[] = {'0', '.', '0', '.', '0', '.', '0', ' ', 'a', '.', 't', '\n', 0xff};
    NSError *error = nil;
    CHECK(NSParseHostsData([NSData dataWithBytes:invalid length:sizeof(invalid)], &error) == nil);
    CHECK(error.localizedDescription.length > 0);
    const unsigned char nul[] = {'#', 0, '\n'};
    CHECK(NSParseHostsData([NSData dataWithBytes:nul length:sizeof(nul)], NULL) == nil);
    CHECK(NSParseHostsData([NSMutableData dataWithLength:NSHostsMaximumBytes + 1], NULL) == nil);
    NSMutableData *boundary = [NSMutableData dataWithLength:NSHostsMaximumBytes];
    memset(boundary.mutableBytes, ' ', boundary.length);
    ((unsigned char *)boundary.mutableBytes)[0] = '#';
    result = NSParseHostsData(boundary, NULL);
    CHECK(result != nil && result.domainKeys.count == 0);
    NSMutableString *many = [NSMutableString new];
    for (NSString *key in Keys(NSMaximumRules)) {
        [many appendFormat:@"0.0.0.0 %@\n", [key substringFromIndex:7]];
    }
    CHECK(Parse(many).domainKeys.count == NSMaximumRules);
    [many appendString:@"0.0.0.0 h0000.test\n"];
    CHECK(Parse(many).duplicateCount == 1);
    [many appendString:@"0.0.0.0 overflow.test\n"];
    error = nil;
    CHECK(NSParseHostsData([many dataUsingEncoding:NSUTF8StringEncoding], &error) == nil);
    CHECK(error.localizedDescription.length > 0);
}
static void TestMerge(void) {
    NSMutableDictionary *document = Document(@{@"domain:old.test" : @"block", @"port:443" : @"allow"});
    document[@"rules"] = @{@"test.app" : @"allow"};
    document[@"default"] = @"block";
    document[@"unattributed"] = @"block";
    document[@"allowAppleSystemProcesses"] = @NO;
    document[@"filterSockets"] = @NO;
    document[@"globalDomainAddresses"] = @{@"domain:old.test" : @[ @"ip:192.0.2.8" ]};
    document[@"globalDomainExpirations"] = @{@"domain:old.test" : [NSDate dateWithTimeIntervalSince1970:1]};
    NSData *before = Encode(document);
    NSHostsImportPlan *plan = NSPlanHostsImport(
        @[ @"domain:www.new.test", @"domain:new.test", @"domain:new.test", @"domain:old.test" ], document,
        NULL);
    CHECK(plan != nil);
    CHECK([plan.addedKeys isEqual:@[ @"domain:new.test" ]]);
    CHECK(plan.existingCount == 2 && plan.conflictCount == 0);
    CHECK([plan.globalRules[@"port:443"] isEqual:@"allow"]);
    CHECK([Encode(document) isEqual:before]);
    NSMutableDictionary *merged = [document mutableCopy];
    merged[@"globalRules"] = plan.globalRules;
    for (NSString *key in document) {
        if (![key isEqual:@"globalRules"]) {
            CHECK([merged[key] isEqual:document[key]]);
        }
    }
    CHECK([NSPolicy policyWithDocument:merged error:NULL] != nil);
    NSHostsImportPlan *repeat = NSPlanHostsImport(plan.addedKeys, merged, NULL);
    CHECK(repeat.addedKeys.count == 0 && repeat.existingCount == 1);
    CHECK([repeat.globalRules isEqual:plan.globalRules]);
    NSHostsImportPlan *empty = NSPlanHostsImport(@[], merged, NULL);
    CHECK(empty != nil && empty.addedKeys.count == 0);
    for (NSString *action in @[ @"allow", @"block-inbound", @"block-outbound" ]) {
        for (NSNumber *reverse in @[ @NO, @YES ]) {
            NSDictionary *rules = @{
                @"domain:a.test" : reverse.boolValue ? action : @"block",
                @"domain:www.a.test" : reverse.boolValue ? @"block" : action
            };
            NSHostsImportPlan *conflict =
                NSPlanHostsImport(@[ @"domain:a.test", @"domain:www.a.test" ], Document(rules), NULL);
            CHECK(conflict != nil && conflict.conflictCount == 2);
            CHECK(conflict.existingCount == 0 && conflict.addedKeys.count == 0);
            CHECK([conflict.globalRules isEqual:rules]);
        }
    }
    for (NSString *key in @[ @"domain:a.test", @"domain:www.a.test" ]) {
        NSHostsImportPlan *alias =
            NSPlanHostsImport(@[ @"domain:a.test", @"domain:www.a.test" ], Document(@{key : @"block"}), NULL);
        CHECK(alias.existingCount == 2 && alias.addedKeys.count == 0);
    }
    for (NSString *bad in @[ @"a.test", @"domain:A.test", @"domain:a.test.", @"ip:192.0.2.1", @"port:53" ]) {
        CHECK(NSPlanHostsImport(@[ bad ], document, NULL) == nil);
        CHECK([Encode(document) isEqual:before]);
    }
    CHECK(NSPlanHostsImport((id) @[ @42 ], document, NULL) == nil);
    CHECK(NSPlanHostsImport((id) @{}, document, NULL) == nil);
    NSMutableDictionary *invalid = [document mutableCopy];
    invalid[@"default"] = @"invalid";
    CHECK(NSPlanHostsImport(@[ @"domain:new.test" ], invalid, NULL) == nil);
}
static void TestLimitsAndPolicy(void) {
    NSMutableDictionary *document = Document(@{});
    NSData *before = Encode(document);
    NSArray *keys = Keys(NSMaximumRules);
    NSHostsImportPlan *full = NSPlanHostsImport(keys, document, NULL);
    CHECK(full != nil && full.globalRules.count == NSMaximumRules);
    CHECK(full.addedKeys.count == NSMaximumRules);
    CHECK([Encode(document) isEqual:before]);
    CHECK(NSPlanHostsImport(Keys(NSMaximumRules + 1), document, NULL) == nil);
    document[@"globalRules"] = full.globalRules;
    before = Encode(document);
    CHECK(NSPlanHostsImport(@[ @"domain:overflow.test" ], document, NULL) == nil);
    CHECK([Encode(document) isEqual:before]);
    NSHostsImportPlan *noop = NSPlanHostsImport(keys, document, NULL);
    CHECK(noop != nil && noop.existingCount == NSMaximumRules && noop.addedKeys.count == 0);
    NSMutableDictionary *almost = [full.globalRules mutableCopy];
    [almost removeObjectForKey:keys.lastObject];
    document[@"globalRules"] = almost;
    CHECK(NSPlanHostsImport(@[ keys.lastObject ], document, NULL).globalRules.count == NSMaximumRules);
    document[@"legacyMetadata"] = [NSMutableData dataWithLength:NSMaximumDocumentBytes];
    before = Encode(document);
    NSError *error = nil;
    CHECK(NSPlanHostsImport(@[], document, &error) == nil);
    CHECK(error.localizedDescription.length > 0);
    CHECK([Encode(document) isEqual:before]);
    document = Document(@{});
    document[@"rules"] = @{@"test.app" : @"allow"};
    document[@"default"] = @"allow";
    NSHostsImportPlan *plan = NSPlanHostsImport(@[ @"domain:ads.test" ], document, NULL);
    document[@"globalRules"] = plan.globalRules;
    NSPolicy *policy = [NSPolicy policyWithDocument:document error:NULL];
    CHECK(policy != nil);
    for (NSString *host in NSGlobalDomainAliases(@"domain:ads.test")) {
        CHECK(![policy allowsIdentity:@"test.app"
                            direction:NSFlowDirectionOutbound
                          destination:@{@"domain" : host}]);
        CHECK(![policy allowsIdentity:@"com.apple.example"
                            direction:NSFlowDirectionInbound
                          destination:@{@"domain" : host}]);
        CHECK(![policy requiresPermissionForIdentity:@"unknown.app" destination:@{@"domain" : host}]);
    }
    CHECK([policy allowsIdentity:@"test.app"
                       direction:NSFlowDirectionOutbound
                     destination:@{@"domain" : @"other.test"}]);
    document[@"globalRules"] = @{@"domain:ads.test" : @"block", @"ip:192.0.2.1" : @"allow"};
    policy = [NSPolicy policyWithDocument:document error:NULL];
    CHECK([policy allowsIdentity:@"test.app"
                       direction:NSFlowDirectionOutbound
                     destination:@{@"domain" : @"ads.test", @"address" : @"192.0.2.1"}]);
    // Existing exact-domain priority differs by queried alias; importer must preserve both.
    document[@"globalRules"] = @{@"domain:ads.test" : @"allow", @"domain:www.ads.test" : @"block"};
    policy = [NSPolicy policyWithDocument:document error:NULL];
    CHECK([policy allowsIdentity:@"test.app"
                       direction:NSFlowDirectionOutbound
                     destination:@{@"domain" : @"ads.test"}]);
    CHECK(![policy allowsIdentity:@"test.app"
                        direction:NSFlowDirectionOutbound
                      destination:@{@"domain" : @"www.ads.test"}]);
}
static BOOL Commit(NSArray *previewAddedKeys, NSError **error) {
    return NSUpdatePolicy(
        ^BOOL(NSMutableDictionary *document, NSError **mutationError) {
            NSHostsImportPlan *plan = NSPlanHostsImport(previewAddedKeys, document, mutationError);
            if (!plan || !plan.addedKeys.count) {
                return NO;
            }
            NSApplyHostsImportPlan(plan, document);
            return YES;
        },
        error);
}
static void TestTransactions(void) {
    // Called at the end of native main. Restore the outer test container before deleting our own.
    NSURL *outer = [NSSharedURL(NSPolicyFile) URLByDeletingLastPathComponent];
    NSURL *root =
        [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                   isDirectory:YES];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL]);
    NSSetTestContainer(root);
    @try {
        NSMutableDictionary *document =
            Document(@{@"domain:skip.test" : @"allow", @"domain:old.test" : @"block"});
        document[@"rules"] = @{@"test.app" : @"block-inbound"};
        document[@"default"] = @"allow";
        document[@"filterSockets"] = @NO;
        document[@"allowAppleSystemProcesses"] = @NO;
        document[@"globalDomainAddresses"] = @{@"domain:old.test" : @[ @"ip:192.0.2.9" ]};
        document[@"globalDomainExpirations"] =
            @{@"domain:old.test" : [NSDate dateWithTimeIntervalSince1970:1]};
        CHECK(NSWriteDocument(document, NSPolicyFile, NULL));
        NSData *disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        NSHostsImportPlan *preview =
            NSPlanHostsImport(@[ @"domain:skip.test", @"domain:new.test", @"domain:race.test" ],
                              NSReadPolicy(NULL).document, NULL);
        CHECK([preview.addedKeys isEqual:@[ @"domain:new.test", @"domain:race.test" ]]);
        CHECK(preview.conflictCount == 1);
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        // A formerly excluded domain becomes eligible, while a preview addition becomes a conflict.
        CHECK(NSUpdatePolicy(
            ^BOOL(NSMutableDictionary *latest, NSError **error) {
                NSMutableDictionary *rules = [latest[@"globalRules"] mutableCopy];
                [rules removeObjectForKey:@"domain:skip.test"];
                rules[@"domain:www.race.test"] = @"block-outbound";
                latest[@"globalRules"] = rules;
                latest[@"unattributed"] = @"block";
                return YES;
            },
            NULL));
        NSDictionary *latest = NSReadPolicy(NULL).document;
        NSHostsImportPlan *replan = NSPlanHostsImport(preview.addedKeys, latest, NULL);
        CHECK([replan.addedKeys isEqual:@[ @"domain:new.test" ]]);
        CHECK(replan.conflictCount == 1);
        CHECK(Commit(preview.addedKeys, NULL));
        NSDictionary *saved = NSReadPolicy(NULL).document;
        CHECK([saved[@"globalRules"][@"domain:new.test"] isEqual:@"block"]);
        CHECK(saved[@"globalRules"][@"domain:skip.test"] == nil);
        CHECK(saved[@"globalRules"][@"domain:race.test"] == nil);
        CHECK([saved[@"globalRules"][@"domain:www.race.test"] isEqual:@"block-outbound"]);
        for (NSString *key in latest) {
            if (![key isEqual:@"globalRules"] && ![key isEqual:@"revision"]) {
                CHECK([saved[key] isEqual:latest[key]]);
            }
        }
        disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        CHECK(!Commit(preview.addedKeys, NULL));
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        CHECK([NSReadPolicy(NULL).document[@"globalRules"] isEqual:saved[@"globalRules"]]);
        disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        NSError *error = nil;
        CHECK(!Commit(@[ @"domain:INVALID.test" ], &error));
        CHECK(error.localizedDescription.length > 0);
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        CHECK(!NSUpdatePolicy(
            ^BOOL(NSMutableDictionary *candidate, NSError **mutationError) {
                candidate[@"oversizedLegacy"] = [NSMutableData dataWithLength:NSMaximumDocumentBytes];
                NSHostsImportPlan *plan =
                    NSPlanHostsImport(@[ @"domain:size.test" ], candidate, mutationError);
                if (!plan) {
                    return NO;
                }
                candidate[@"globalRules"] = plan.globalRules;
                return YES;
            },
            NULL));
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        // Simulate an orphan live DNS record. Preview must not activate it when adding the key.
        NSMutableDictionary *orphan = [NSReadPolicy(NULL).document mutableCopy];
        NSMutableDictionary *addresses = [orphan[@"globalDomainAddresses"] mutableCopy];
        NSMutableDictionary *expirations = [orphan[@"globalDomainExpirations"] mutableCopy];
        addresses[@"domain:orphan.test"] = @[ @"ip:192.0.2.200" ];
        expirations[@"domain:orphan.test"] = [NSDate dateWithTimeIntervalSinceNow:120];
        orphan[@"globalDomainAddresses"] = addresses;
        orphan[@"globalDomainExpirations"] = expirations;
        CHECK(NSWriteDocument(orphan, NSPolicyFile, NULL));
        NSPolicy *beforeOrphan = NSReadPolicy(NULL);
        CHECK([beforeOrphan allowsIdentity:@"other.app"
                                 direction:NSFlowDirectionOutbound
                               destination:@{@"address" : @"192.0.2.200"}]);
        disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        NSHostsImportPlan *orphanPlan =
            NSPlanHostsImport(@[ @"domain:orphan.test" ], beforeOrphan.document, NULL);
        CHECK(orphanPlan != nil && orphanPlan.addedKeys.count == 1);
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        CHECK(Commit(orphanPlan.addedKeys, NULL));
        NSPolicy *afterOrphan = NSReadPolicy(NULL);
        CHECK(afterOrphan.document[@"globalDomainAddresses"][@"domain:orphan.test"] == nil);
        CHECK(afterOrphan.document[@"globalDomainExpirations"][@"domain:orphan.test"] == nil);
        CHECK([afterOrphan.document[@"globalDomainAddresses"][@"domain:old.test"]
            isEqual:beforeOrphan.document[@"globalDomainAddresses"][@"domain:old.test"]]);
        CHECK([afterOrphan allowsIdentity:@"other.app"
                                direction:NSFlowDirectionOutbound
                              destination:@{@"address" : @"192.0.2.200"}]);
        CHECK(![afterOrphan allowsIdentity:@"other.app"
                                 direction:NSFlowDirectionOutbound
                               destination:@{@"domain" : @"orphan.test"}]);
        disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        NSStoreLock *held = [NSStoreLock tryLockURL:NSSharedURL(@"policy.lock") error:NULL];
        CHECK(held != nil);
        CHECK(!Commit(@[ @"domain:locked.test" ], NULL));
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
        [held unlock];
        NSHostsImportPlan *full = NSPlanHostsImport(Keys(NSMaximumRules), Document(@{}), NULL);
        CHECK(NSWriteDocument(Document(full.globalRules), NSPolicyFile, NULL));
        disk = [NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)];
        CHECK(!Commit(@[ @"domain:overflow.test" ], NULL));
        CHECK([[NSData dataWithContentsOfURL:NSSharedURL(NSPolicyFile)] isEqual:disk]);
    } @finally {
        NSSetTestContainer(outer);
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    }
}

NSUInteger RunHostsImportTests(void) {
    checks = 0;
    TestParsing();
    TestMerge();
    TestLimitsAndPolicy();
    TestTransactions();
    NSLog(@"Passed %lu Hosts import checks", (unsigned long)checks);
    return checks;
}
