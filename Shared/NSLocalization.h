#ifndef NS_LOCALIZATION_H
#define NS_LOCALIZATION_H

#import <Foundation/Foundation.h>

// English source keys also provide the fallback for bundles without resources.
static inline NSString *NSL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:@"Localizable"];
}

#endif
