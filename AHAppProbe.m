// AHAppProbe.m
#import "AHAppProbe.h"

@implementation AHAppProbe

+ (BOOL)isInsideAihuishou {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *lower = bid.lowercaseString;
    // 历史 bundle id：com.aihuishou / com.aihuishou.consumer / loverecycle 系列
    NSArray *known = @[@"com.aihuishou",
                       @"aihuishou",
                       @"com.loverecycle",
                       @"loverecycle"];
    for (NSString *k in known) {
        if ([lower containsString:k.lowercaseString]) return YES;
    }
    return NO;
}

@end
