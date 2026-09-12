//
//  AHCaptureEngine.m
//  AihuishouBatchFind
//

#import "AHCaptureEngine.h"
#import <objc/runtime.h>

@interface AHCaptureEngine ()
@property (nonatomic, weak) UIScrollView *autoListView;
@property (nonatomic, assign) NSInteger autoPage;
@property (nonatomic, assign) NSInteger autoMaxPages;
@property (nonatomic, assign) NSInteger autoTotalSaved;
@property (nonatomic, assign) BOOL autoStopFlag;
@property (nonatomic, copy) void (^autoProgress)(NSInteger page, NSInteger totalSaved);
@property (nonatomic, copy) void (^autoCompletion)(NSInteger totalSaved);
@property (nonatomic, strong) NSMutableSet<NSString *> *seenFingerprints;
@end


@implementation AHCaptureEngine

+ (instancetype)shared {
    static AHCaptureEngine *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[AHCaptureEngine alloc] init];
        s.recentEndpoints = [NSMutableArray array];
        s.seenFingerprints = [NSMutableSet set];
    });
    return s;
}

#pragma mark - 网络嗅探

- (void)handleRequest:(NSURLRequest *)request
             response:(NSURLResponse *)response
                 data:(NSData *)data {
    if (!self.sniffEnabled) return;
    if (!data.length) return;

    self.sniffRequests++;

    id json = nil;
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    } @catch (NSException *e) {
        json = nil;
    }
    if (!json) return;

    NSInteger n = [self extractAndSaveFromJSON:json];
    if (n > 0) {
        self.sniffHits += n;
        [self addEndpoint:request.URL.absoluteString ?: @""];
    }
}

- (void)addEndpoint:(NSString *)url {
    if (!url.length) return;
    NSString *shortURL = url.length > 120 ? [url substringToIndex:120] : url;
    if (![self.recentEndpoints containsObject:shortURL]) {
        [self.recentEndpoints insertObject:shortURL atIndex:0];
        if (self.recentEndpoints.count > 20) {
            [self.recentEndpoints removeLastObject];
        }
    }
}

#pragma mark - 界面抓取：单屏

- (NSInteger)captureVisibleOnce {
    UIScrollView *list = [[self class] findBestListView];
    if (!list) return 0;

    NSArray<UIView *> *cells = [[self class] cellViewsIn:list];
    NSInteger saved = 0;

    for (UIView *cell in cells) {
        NSArray<NSString *> *texts = [[self class] textsInView:cell depth:0];
        AHRecord *r = [[self class] recordFromTexts:texts];
        if (!r) continue;

        // 去重：用关键字段拼指纹
        NSString *fp = [NSString stringWithFormat:@"%@|%@|%@|%@",
                        r.model ?: @"", r.memory ?: @"", r.price ?: @"", r.color ?: @""];
        if (fp.length > 6) {
            if ([self.seenFingerprints containsObject:fp]) continue;
            [self.seenFingerprints addObject:fp];
        }

        r.link = @"（界面抓取）";
        if ([[AHRecordStore sharedStore] insertRecord:r]) saved++;
    }
    return saved;
}

#pragma mark - 界面抓取：自动翻页

- (void)startAutoScrollCaptureMaxPages:(NSInteger)maxPages
                              progress:(void (^)(NSInteger page, NSInteger totalSaved))progress
                            completion:(void (^)(NSInteger totalSaved))completion {
    if (self.autoScrollRunning) return;

    UIScrollView *list = [[self class] findBestListView];
    if (!list) {
        if (completion) completion(0);
        return;
    }

    self.autoListView = list;
    self.autoPage = 0;
    self.autoMaxPages = maxPages;
    self.autoTotalSaved = 0;
    self.autoStopFlag = NO;
    self.autoProgress = progress;
    self.autoCompletion = completion;
    self.autoScrollRunning = YES;

    [self autoScrollStep];
}

- (void)stopAutoScrollCapture {
    self.autoStopFlag = YES;
}

- (void)autoScrollStep {
    __weak typeof(self) wself = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(wself) self = wself;
        if (!self) return;
        if (self.autoStopFlag || !self.autoListView) {
            [self finishAutoScroll];
            return;
        }

        self.autoPage++;
        NSInteger got = [self captureVisibleOnce];
        self.autoTotalSaved += got;

        if (self.autoProgress) self.autoProgress(self.autoPage, self.autoTotalSaved);

        if (self.autoPage >= self.autoMaxPages) {
            [self finishAutoScroll];
            return;
        }

        // 往下滚一屏（80% 高度，留点重叠避免漏）
        UIScrollView *list = self.autoListView;
        CGFloat h = list.bounds.size.height;
        CGFloat maxY = list.contentSize.height - h;
        if (maxY <= 0) { [self finishAutoScroll]; return; }

        CGFloat nextY = MIN(list.contentOffset.y + h * 0.8, maxY);
        BOOL reachedEnd = (list.contentOffset.y >= maxY - 2);

        [list setContentOffset:CGPointMake(list.contentOffset.x, nextY) animated:NO];

        if (reachedEnd) {
            // 到底了，再抓一次收尾
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSInteger tail = [wself captureVisibleOnce];
                wself.autoTotalSaved += tail;
                [wself finishAutoScroll];
            });
            return;
        }

        // 等列表加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [wself autoScrollStep];
        });
    });
}

- (void)finishAutoScroll {
    NSInteger total = self.autoTotalSaved;
    void (^cb)(NSInteger) = self.autoCompletion;
    self.autoScrollRunning = NO;
    self.autoListView = nil;
    self.autoProgress = nil;
    self.autoCompletion = nil;
    if (cb) cb(total);
}

#pragma mark - 列表探测

+ (UIScrollView *)findBestListView {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = UIApplication.sharedApplication.windows.firstObject;
    if (!win) return nil;

    NSMutableArray<UIScrollView *> *candidates = [NSMutableArray array];
    [self collectScrollViews:win into:candidates depth:0];

    UIScrollView *best = nil;
    CGFloat bestScore = 0;
    for (UIScrollView *sv in candidates) {
        CGFloat score = 0;
        if ([sv isKindOfClass:[UITableView class]]) score += 100;
        else if ([sv isKindOfClass:[UICollectionView class]]) score += 100;
        if (sv.window && !sv.hidden && sv.alpha > 0.1) score += 50;
        score += sv.subviews.count * 0.5;
        score += sv.bounds.size.height / 10.0;
        if (score > bestScore) { bestScore = score; best = sv; }
    }
    return best;
}

+ (void)collectScrollViews:(UIView *)v into:(NSMutableArray *)out depth:(NSInteger)depth {
    if (!v || depth > 12) return;
    if ([v isKindOfClass:[UIScrollView class]] && v.bounds.size.height > 120) {
        [out addObject:(UIScrollView *)v];
    }
    for (UIView *sub in v.subviews) {
        [self collectScrollViews:sub into:out depth:depth + 1];
    }
}

+ (NSArray<UIView *> *)cellViewsIn:(UIView *)container {
    NSMutableArray *out = [NSMutableArray array];
    if ([container isKindOfClass:[UITableView class]]) {
        for (UITableViewCell *c in ((UITableView *)container).visibleCells) [out addObject:c];
        if (out.count) return out;
    }
    if ([container isKindOfClass:[UICollectionView class]]) {
        for (UICollectionViewCell *c in ((UICollectionView *)container).visibleCells) [out addObject:c];
        if (out.count) return out;
    }
    [self collectCells:container into:out depth:0];
    return out;
}

+ (void)collectCells:(UIView *)v into:(NSMutableArray *)out depth:(NSInteger)depth {
    if (!v || depth > 12) return;
    if ([v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UICollectionViewCell class]]) {
        [out addObject:v];
        return;
    }
    for (UIView *sub in v.subviews) {
        [self collectCells:sub into:out depth:depth + 1];
    }
}

+ (NSArray<NSString *> *)textsInView:(UIView *)view depth:(NSInteger)depth {
    NSMutableArray *out = [NSMutableArray array];
    if (!view || depth > 14) return out;

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)view).text;
        if (t.length) [out addObject:t];
    } else if ([view isKindOfClass:[UITextView class]]) {
        NSString *t = ((UITextView *)view).text;
        if (t.length) [out addObject:t];
    } else if ([view isKindOfClass:[UIButton class]]) {
        NSString *t = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (t.length) [out addObject:t];
    }

    for (UIView *sub in view.subviews) {
        [out addObjectsFromArray:[self textsInView:sub depth:depth + 1]];
    }
    return out;
}

#pragma mark - 文本启发式解析

+ (NSArray<NSString *> *)colorKeywords {
    static NSArray *k = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        k = @[@"黑色", @"白色", @"蓝色", @"原色", @"钛金属", @"暗紫", @"银色", @"金色",
              @"星光色", @"午夜色", @"远峰蓝", @"苍岭绿", @"深空黑", @"粉色", @"紫色", @"绿色", @"红色", @"黄色"];
    });
    return k;
}

+ (AHRecord *)recordFromTexts:(NSArray<NSString *> *)texts {
    if (!texts.count) return nil;

    NSString *model = nil, *memory = nil, *battery = nil, *ios = nil, *price = nil, *color = nil;

    for (NSString *raw in texts) {
        NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!s.length) continue;

        if (!model && ([s rangeOfString:@"iPhone" options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"iPad"   options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"MacBook" options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"小米"    options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"华为"    options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"荣耀"    options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"OPPO"   options:NSCaseInsensitiveSearch].length ||
                       [s rangeOfString:@"vivo"   options:NSCaseInsensitiveSearch].length)) {
            model = s;
        }

        if (!memory && ([s rangeOfString:@"GB" options:NSCaseInsensitiveSearch].length ||
                        [s rangeOfString:@"TB" options:NSCaseInsensitiveSearch].length)) {
            memory = s;
        }

        if (!battery && [s containsString:@"%"]) battery = s;

        if (!ios && ([s rangeOfString:@"iOS" options:NSCaseInsensitiveSearch].length ||
                     [s containsString:@"系统"])) ios = s;

        if (!price && ([s containsString:@"¥"] || [s containsString:@"￥"] || [s containsString:@"元"])) price = s;

        if (!color) {
            for (NSString *c in [self colorKeywords]) {
                if ([s containsString:c]) { color = c; break; }
            }
        }
    }

    // 至少要认出型号或价格，否则视为非商品 cell
    if (!model && !price) return nil;

    AHRecord *r = [AHRecord new];
    r.model = model;
    r.memory = memory;
    r.battery = battery;
    r.iosVersion = ios;
    r.price = price;
    r.color = color;
    r.note = [texts componentsJoinedByString:@" | "];
    return r;
}

#pragma mark - JSON 递归解析

- (NSInteger)extractAndSaveFromJSON:(id)json {
    if (!json) return 0;

    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    [[self class] collectProductDicts:json into:candidates depth:0];
    if (!candidates.count) return 0;

    NSInteger saved = 0;
    for (NSDictionary *d in candidates) {
        AHRecord *r = [[self class] recordFromDict:d];
        if (!r) continue;

        NSString *fp = [NSString stringWithFormat:@"%@|%@|%@|%@",
                        r.model ?: @"", r.memory ?: @"", r.price ?: @"", r.color ?: @""];
        if (fp.length > 6) {
            if ([self.seenFingerprints containsObject:fp]) continue;
            [self.seenFingerprints addObject:fp];
        }

        if ([[AHRecordStore sharedStore] insertRecord:r]) saved++;
    }
    return saved;
}

+ (void)collectProductDicts:(id)node into:(NSMutableArray *)out depth:(NSInteger)depth {
    if (!node || depth > 8) return;

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)node;
        if ([self scoreProductDict:d] >= 8) [out addObject:d];
        for (id v in d.allValues) {
            [self collectProductDicts:v into:out depth:depth + 1];
        }
    } else if ([node isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)node) {
            [self collectProductDicts:v into:out depth:depth + 1];
        }
    }
}

/// 给字典打分，判断它像不像一条「机器记录」
+ (NSInteger)scoreProductDict:(NSDictionary *)d {
    static NSArray *modelKeys = nil, *priceKeys = nil, *memKeys = nil, *battKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        modelKeys = @[@"model", @"title", @"name", @"goodsname", @"productname", @"skuname",
                      @"型号", @"标题", @"商品名称", @"机型", @"devicename", @"machinename"];
        priceKeys = @[@"price", @"saleprice", @"amount", @"sellprice", @"pricestr",
                      @"价格", @"售价", @"到手价"];
        memKeys   = @[@"memory", @"storage", @"capacity", @"rom", @"ram",
                      @"内存", @"容量", @"机身内存"];
        battKeys  = @[@"battery", @"batteryhealth", @"health", @"电量", @"电池", @"电池健康"];
    });

    NSInteger score = 0;

    for (NSString *k in d.allKeys) {
        NSString *lk = k.lowercaseString;
        id v = d[k];

        // 值里出现机型关键字 -> 强信号
        if ([v isKindOfClass:[NSString class]]) {
            NSString *s = [(NSString *)v lowercaseString];
            if ([s containsString:@"iphone"] || [s containsString:@"ipad"]) score += 10;
        }

        for (NSString *want in modelKeys) if ([lk isEqualToString:want] || [lk containsString:want]) { score += 3; break; }
        for (NSString *want in priceKeys) if ([lk isEqualToString:want] || [lk containsString:want]) { score += 3; break; }
        for (NSString *want in memKeys)   if ([lk isEqualToString:want] || [lk containsString:want]) { score += 2; break; }
        for (NSString *want in battKeys)  if ([lk isEqualToString:want] || [lk containsString:want]) { score += 2; break; }
    }
    return score;
}

+ (AHRecord *)recordFromDict:(NSDictionary *)d {
    NSString *model = [self stringInDict:d keys:@[@"model", @"title", @"name", @"goodsName",
                                                   @"productName", @"skuName", @"型号", @"标题",
                                                   @"商品名称", @"机型", @"deviceName", @"machineName"]];
    NSString *price = [self stringInDict:d keys:@[@"price", @"salePrice", @"sellPrice", @"amount",
                                                   @"priceStr", @"价格", @"售价", @"到手价"]];

    // 至少要认出型号或价格
    if (!model.length && !price.length) return nil;

    AHRecord *r = [AHRecord new];
    r.model      = model;
    r.price      = price;
    r.memory     = [self stringInDict:d keys:@[@"memory", @"storage", @"capacity", @"rom", @"内存", @"容量", @"机身内存"]];
    r.battery    = [self stringInDict:d keys:@[@"battery", @"batteryHealth", @"health", @"电量", @"电池", @"电池健康"]];
    r.color      = [self stringInDict:d keys:@[@"color", @"colour", @"颜色", @"机身颜色"]];
    r.iosVersion = [self stringInDict:d keys:@[@"version", @"system", @"osVersion", @"系统", @"版本", @"系统版本"]];
    r.seller     = [self stringInDict:d keys:@[@"seller", @"shopName", @"merchant", @"商家", @"卖家", @"店铺"]];
    r.note       = @"（网络嗅探）";
    return r;
}

+ (NSString *)stringInDict:(NSDictionary *)d keys:(NSArray<NSString *> *)keys {
    for (NSString *want in keys) {
        NSString *wantLower = want.lowercaseString;
        for (NSString *k in d.allKeys) {
            NSString *lk = k.lowercaseString;
            if (![lk isEqualToString:wantLower] && ![lk containsString:wantLower]) continue;

            id v = d[k];
            if ([v isKindOfClass:[NSString class]]) return v;
            if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
        }
    }
    return nil;
}

@end
