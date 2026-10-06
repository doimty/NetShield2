#import "NSLocalization.h"
#import "NSHostsImport.h"
#import "NSConstants.h"
#import "NSGlobalRule.h"
#import "NSPolicy.h"

@interface NSHostsImportResult ()
@property(nonatomic, readwrite, copy) NSArray<NSString *> *domainKeys;
@property(nonatomic, readwrite) NSHostsParseStats stats;
@property(nonatomic, readwrite) NSUInteger duplicateCount;
@end
@implementation NSHostsImportResult
@end

@interface NSHostsImportPlan ()
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *globalRules;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *addedKeys;
@property(nonatomic, readwrite) NSUInteger existingCount;
@property(nonatomic, readwrite) NSUInteger conflictCount;
@end
@implementation NSHostsImportPlan
@end

void NSApplyHostsImportPlan(NSHostsImportPlan *plan, NSMutableDictionary *document) {
    document[@"globalRules"] = plan.globalRules;
    for (NSString *field in @[ @"globalDomainAddresses", @"globalDomainExpirations" ]) {
        if (document[field]) {
            NSMutableDictionary *cache = [document[field] mutableCopy];
            [cache removeObjectsForKeys:plan.addedKeys];
            document[field] = cache;
        }
    }
}
static void NSHostsError(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:@"NetShield2.HostsImport"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    }
}
static bool NSCollectHostsDomain(const char *domain, void *context) {
    NSMutableSet *keys = (__bridge NSMutableSet *)context;
    [keys addObject:[@"domain:" stringByAppendingString:@(domain)]];
    return keys.count <= NSMaximumRules;
}
NSHostsImportResult *NSParseHostsData(NSData *data, NSError **error) {
    if (![data isKindOfClass:NSData.class]) {
        NSHostsError(error, NSL(@"Hosts input must be UTF-8 data."));
        return nil;
    }
    NSMutableSet *keys = [NSMutableSet new];
    NSHostsParseStats stats;
    NSHostsParseStatus status =
        NSHostsParse(data.bytes, data.length, NSCollectHostsDomain, (__bridge void *)keys, &stats);
    if (status != NSHostsParseOK) {
        NSString *message =
            status == NSHostsParseTooLarge ? NSL(@"Hosts input exceeds the 2 MiB limit.")
            : status == NSHostsParseInvalidEncoding
                ? NSL(@"Hosts input must be valid UTF-8 without NUL bytes.")
                : NSL(@"Hosts input exceeds the 4096 unique domain limit; nothing was imported.");
        NSHostsError(error, message);
        return nil;
    }
    NSHostsImportResult *result = [NSHostsImportResult new];
    result.domainKeys = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
    result.stats = stats;
    result.duplicateCount = stats.acceptedNames - keys.count;
    return result;
}
NSHostsImportPlan *NSPlanHostsImport(NSArray<NSString *> *domainKeys, NSDictionary *document,
                                     NSError **error) {
    if (![domainKeys isKindOfClass:NSArray.class] || domainKeys.count > NSMaximumRules) {
        NSHostsError(error, NSL(@"Import requires an array of at most 4096 canonical domain keys."));
        return nil;
    }
    for (id key in domainKeys) {
        if (![key isKindOfClass:NSString.class] || ![key hasPrefix:@"domain:"] ||
            !NSValidGlobalRuleKey(key)) {
            NSHostsError(error, NSL(@"Import contains a noncanonical or invalid domain key."));
            return nil;
        }
    }
    if (![NSPolicy policyWithDocument:document error:error]) {
        return nil;
    }
    NSMutableDictionary *rules = [document[@"globalRules"] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableArray *added = [NSMutableArray new];
    NSUInteger existing = 0, conflicts = 0;
    NSArray *keys =
        [[[NSSet setWithArray:domainKeys] allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        BOOL blocked = NO, conflict = NO;
        // Inspect BOTH aliases before choosing a disposition: a block must never hide an allow.
        for (NSString *host in NSGlobalDomainAliases(key)) {
            NSString *action = rules[[@"domain:" stringByAppendingString:host]];
            blocked |= [action isEqual:@"block"];
            conflict |= action != nil && ![action isEqual:@"block"];
        }
        if (conflict) {
            conflicts++;
        } else if (blocked) {
            existing++;
        } else {
            rules[key] = @"block";
            [added addObject:key];
        }
    }
    if (rules.count > NSMaximumRules) {
        NSHostsError(error, NSL(@"Import would exceed 4096 global rules; nothing was imported."));
        return nil;
    }
    NSHostsImportPlan *plan = [NSHostsImportPlan new];
    plan.globalRules = rules;
    plan.addedKeys = added;
    plan.existingCount = existing;
    plan.conflictCount = conflicts;
    NSMutableDictionary *candidate = [document mutableCopy];
    NSApplyHostsImportPlan(plan, candidate);
    NSPolicy *validated = [NSPolicy policyWithDocument:candidate error:error];
    if (!validated) {
        return nil;
    }
    // Check the unmodified metadata too, including unknown/legacy fields and old DNS state.
    for (NSDictionary *encodedDocument in @[ candidate, validated.document ]) {
        NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:encodedDocument
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0
                                                                      error:error];
        if (!encoded) {
            return nil;
        }
        if (encoded.length > NSMaximumDocumentBytes) {
            NSHostsError(error, NSL(@"Resulting policy exceeds the 2 MiB limit; nothing was imported."));
            return nil;
        }
    }
    return plan;
}
