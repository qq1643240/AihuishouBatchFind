//
//  AHCaptureEngine.h
//  AihuishouBatchFind
//
//  真实数据抓取引擎
//  ├─ 界面抓取：遍历列表 cell 文本自动解析（无需知道接口，立即可用）
//  └─ 网络嗅探：拦截 NSURLSession 真实 JSON 响应（字段更全）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "AHRecordStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AHCaptureMode) {
    AHCaptureModeUI      = 0,   // 界面抓取
    AHCaptureModeNetwork = 1,   // 网络嗅探
};

@interface AHCaptureEngine : NSObject

+ (instancetype)shared;

#pragma mark - 网络嗅探

@property (nonatomic, assign) BOOL sniffEnabled;                            // 是否拦截
@property (nonatomic, assign) NSUInteger sniffRequests;                    // 已捕获请求数
@property (nonatomic, assign) NSUInteger sniffHits;                        // 从 JSON 入库条数
@property (nonatomic, strong) NSMutableArray<NSString *> *recentEndpoints; // 最近命中的接口

/// 由 Tweak.xm 里的 NSURLSession 钩子调用
- (void)handleRequest:(NSURLRequest *)request
             response:(nullable NSURLResponse *)response
                 data:(nullable NSData *)data;

#pragma mark - 界面抓取

@property (nonatomic, assign) BOOL autoScrollRunning;

/// 抓取当前屏幕可见列表一屏，返回本次入库条数
- (NSInteger)captureVisibleOnce;

/// 自动翻页批量抓取
- (void)startAutoScrollCaptureMaxPages:(NSInteger)maxPages
                              progress:(void (^)(NSInteger page, NSInteger totalSaved))progress
                            completion:(void (^)(NSInteger totalSaved))completion;

/// 停止自动翻页
- (void)stopAutoScrollCapture;

#pragma mark - 解析

/// 从任意 JSON 递归找出「像机器记录」的字典并入库，返回条数
- (NSInteger)extractAndSaveFromJSON:(id)json;

/// UI 文本数组 -> 记录（启发式），识别不出返回 nil
+ (nullable AHRecord *)recordFromTexts:(NSArray<NSString *> *)texts;

/// JSON 字典 -> 记录
+ (nullable AHRecord *)recordFromDict:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
