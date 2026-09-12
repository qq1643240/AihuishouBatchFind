// AHBatchFindProxy.h
// 单例代理：接收注入按钮点击、定位当前 Top VC、展示批量查找界面
// 解耦了 UIBarButtonItem 的 target 选择，避免循环引用。

#import <UIKit/UIKit.h>

@interface AHBatchFindProxy : NSObject

+ (instancetype)sharedProxy;

// 由注入按钮调用
- (void)onTapInjectedButton:(UIBarButtonItem *)sender;

// 当前展示的批量查找 VC 在 dismiss 后会清空；Tweak 不依赖此引用
@property (nonatomic, weak) UIViewController *currentPresenter;

@end
