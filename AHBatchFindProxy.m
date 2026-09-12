// AHBatchFindProxy.m
#import "AHBatchFindProxy.h"
#import "AHBatchFindController.h"

@implementation AHBatchFindProxy

+ (instancetype)sharedProxy {
    static AHBatchFindProxy *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[AHBatchFindProxy alloc] init];
    });
    return s_instance;
}

- (void)onTapInjectedButton:(UIBarButtonItem *)sender {
    UIViewController *top = [self _topViewController];
    if (!top) return;

    AHBatchFindController *ctl = [[AHBatchFindController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:ctl];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;

    self.currentPresenter = top;
    [top presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Find Top View Controller

- (UIViewController *)_topViewController {
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    if (!root) return nil;

    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    if ([root isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)root;
        UIViewController *sel = tab.selectedViewController;
        while (sel.presentedViewController) sel = sel.presentedViewController;
        if ([sel isKindOfClass:[UINavigationController class]]) {
            UIViewController *top = ((UINavigationController *)sel).topViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            return top;
        }
        return sel;
    }
    return root;
}

@end
