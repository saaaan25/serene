#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlexDelegateBridge : NSObject

+ (int64_t)createDelegate;
+ (void)disposeDelegate;

@end

NS_ASSUME_NONNULL_END