#import <Foundation/Foundation.h>

// Bug: no nullability annotations (no NS_ASSUME_NONNULL_BEGIN/END, no nullable/nonnull on the parameter or block).
@interface LegacyHelper : NSObject

@property (nonatomic, copy) NSString *lastResult;

- (void)fetchDataWithCompletion:(void (^)(NSString *result))completion;

@end
