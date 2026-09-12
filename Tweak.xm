// AihuishouBatchFind/Tweak.xm
// 爱回收「严选二手」批量查找插件 —— 主入口（Logos 钩子）
//
// 本文件通过 Logos 语法经由 Cydia Substrate / Substitute 注入到爱回收 App。
// 主要职责：
//   1. 监听 UIViewController 生命周期
//   2. 多种启发式识别「严选二手」相关页面（标题/类名）
//   3. 注入导航栏「批量查找」+「真实抓取」两个按钮
//   4. 钩 NSURLSession 拦截真实 API 响应，供「网络嗅探」模式使用
//
// ⚠️ 爱回收 App 的真实类名/搜索接口未公开；
//   如类名启发式规则命中错误或缺失，请用 class-dump 得到的真实类名
//   替换 isTarget 判断条件中的关键字。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AHAppProbe.h"
#import "AHBatchFindProxy.h"
#import "AHCaptureEngine.h"

static const void *kAHBatchFindInjectedKey = &kAHBatchFindInjectedKey;

%group AHBGroup

// ─────────────────────────────────────────────────────────────
// 1) 注入导航栏按钮
// ─────────────────────────────────────────────────────────────
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // 已经注入过：跳过
    if (objc_getAssociatedObject(self, kAHBatchFindInjectedKey)) return;
    // 不在爱回收 App：跳过
    if (![AHAppProbe isInsideAihuishou]) return;

    NSString *tabTitle = self.tabBarItem.title ?: @"";
    NSString *navTitle = self.navigationItem.title ?: @"";
    NSString *clsName  = NSStringFromClass([self class]);

    // 多条件启发式识别「严选二手」
    BOOL isTarget =
        [tabTitle containsString:@"严选"]      ||
        [navTitle containsString:@"严选"]      ||
        [clsName  containsString:@"Yanxuan"]   ||
        [clsName  containsString:@"Strict"]    ||
        [clsName  containsString:@"Second"]    ||
        [clsName  containsString:@"Used"]      ||
        [clsName  containsString:@"Hand"]      ||
        [clsName  containsString:@"AHSecond"]  ||
        [clsName  containsString:@"AHSelect"];

    if (!isTarget) return;

    // 同一 VC 上仅注入一次
    objc_setAssociatedObject(self, kAHBatchFindInjectedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    AHBatchFindProxy *proxy = [AHBatchFindProxy sharedProxy];

    UIBarButtonItem *realItem =
        [[UIBarButtonItem alloc] initWithTitle:@"真实抓取"
                                          style:UIBarButtonItemStylePlain
                                         target:proxy
                                         action:@selector(onTapRealScrape:)];
    UIBarButtonItem *batchItem =
        [[UIBarButtonItem alloc] initWithTitle:@"批量查找"
                                          style:UIBarButtonItemStylePlain
                                         target:proxy
                                         action:@selector(onTapInjectedButton:)];

    realItem.accessibilityLabel  = @"AHRealScrapeButton";
    batchItem.accessibilityLabel = @"AHBatchFindButton";

    self.navigationItem.rightBarButtonItems = @[realItem, batchItem];
}

%end


// ─────────────────────────────────────────────────────────────
// 2) 网络嗅探：拦截 NSURLSession 真实响应
//    仅在 sniffEnabled == YES 时包装回调；关闭时零开销直接透传。
// ─────────────────────────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    if (![AHCaptureEngine shared].sniffEnabled) {
        return %orig;
    }

    void (^wrapped)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable) =
        ^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            [[AHCaptureEngine shared] handleRequest:request response:response data:data];
            if (completionHandler) completionHandler(data, response, error);
        };

    return %orig(request, wrapped);
}

%end

%end  // group AHBGroup

%ctor {
    @autoreleasepool {
        %init(AHBGroup);
    }
}
