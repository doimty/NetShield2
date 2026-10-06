#import <Foundation/Foundation.h>
#import "NSHostsParser.h"

NS_ASSUME_NONNULL_BEGIN
@interface NSHostsImportResult : NSObject
@property(nonatomic, readonly, copy) NSArray<NSString *> *domainKeys;
@property(nonatomic, readonly) NSHostsParseStats stats;
@property(nonatomic, readonly) NSUInteger duplicateCount;
@end

@interface NSHostsImportPlan : NSObject
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *globalRules;
@property(nonatomic, readonly, copy) NSArray<NSString *> *addedKeys;
@property(nonatomic, readonly) NSUInteger existingCount;
@property(nonatomic, readonly) NSUInteger conflictCount;
@end

// Exact domain keys, sorted and deduplicated. Capacity errors never return a partial result.
FOUNDATION_EXPORT NSHostsImportResult *_Nullable NSParseHostsData(NSData *data,
                                                                  NSError *_Nullable *_Nullable error);
// Pure preview/replan; preserves all existing actions and never modifies document.
// At commit, pass ONLY the preview's addedKeys against the latest locked document.
FOUNDATION_EXPORT NSHostsImportPlan *_Nullable NSPlanHostsImport(NSArray<NSString *> *domainKeys,
                                                                 NSDictionary *document,
                                                                 NSError *_Nullable *_Nullable error);
// Apply only a plan just computed against this document (under NSUpdatePolicy at commit).
// Clear orphan DNS state for additions, never the cache of skipped existing rules.
FOUNDATION_EXPORT void NSApplyHostsImportPlan(NSHostsImportPlan *plan, NSMutableDictionary *document);
NS_ASSUME_NONNULL_END
