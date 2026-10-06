#import <UIKit/UIKit.h>

@interface NSHostsImportController : UIViewController
@property(nonatomic, copy) void (^didImport)(NSUInteger count);
@end
