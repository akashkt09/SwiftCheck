#import "LegacyHelper.h"

@implementation LegacyHelper

- (void)fetchDataWithCompletion:(void (^)(NSString *result))completion {
    // Bug: block captures self strongly — should capture a weak reference to avoid a retain cycle.
    dispatch_async(dispatch_get_main_queue(), ^{
        self.lastResult = @"done";
        completion(self.lastResult);
    });
}

@end
