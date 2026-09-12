// AHProgressHUD.h
// 浮层进度提示：开始时 show，进行中 updateTitle:progress:，结束 dismiss
// 使用独立的 UIWindow（最高 level），绕开爱回收 App 的复杂容器层级

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AHProgressHUD : NSObject

+ (void)showWithTitle:(nullable NSString *)title;
+ (void)updateTitle:(nullable NSString *)title progress:(double)p;  // 0..1
+ (void)dismiss;

@end

NS_ASSUME_NONNULL_END
