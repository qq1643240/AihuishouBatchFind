// AHExporter.m
#import "AHExporter.h"
#import <UIKit/UIKit.h>

@implementation AHExporter

#pragma mark - 路径 / 文件名

+ (NSString *)_docPath:(NSString *)filename {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [dir stringByAppendingPathComponent:filename];
}

+ (NSString *)_ts {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    return [fmt stringFromDate:[NSDate date]];
}

#pragma mark - 行格式化

+ (NSString *)_singleLine:(AHRecord *)r {
    return [NSString stringWithFormat:
            @"型号: %@\n内存: %@\n颜色: %@\n电池: %@\n系统: %@\n价格: %@\n"
            @"卖家: %@\n链接: %@\n备注: %@\n采集时间: %@\n",
            r.model ?: @"-", r.memory ?: @"-", r.color ?: @"-",
            r.battery ?: @"-", r.iosVersion ?: @"-", r.price ?: @"-",
            r.seller ?: @"-", r.link ?: @"-", r.note ?: @"-",
            r.capturedAt ?: @"-"];
}

#pragma mark - 复制

+ (void)copySingleRecord:(AHRecord *)r {
    if (!r) return;
    [UIPasteboard generalPasteboard].string = [self _singleLine:r];
}

+ (NSInteger)copyAllRecords:(NSArray<AHRecord *> *)records {
    NSArray *list = records ?: [[AHRecordStore sharedStore] allRecords];
    if (!list.count) {
        [UIPasteboard generalPasteboard].string = @"";
        return 0;
    }
    NSMutableString *m = [NSMutableString string];
    [m appendString:@"型号\t内存\t颜色\t电池\t系统\t价格\t卖家\t链接\t备注\t采集时间\n"];
    for (AHRecord *r in list) {
        [m appendFormat:@"%@\t%@\t%@\t%@\t%@\t%@\t%@\t%@\t%@\t%@\n",
         r.model ?: @"-", r.memory ?: @"-", r.color ?: @"-",
         r.battery ?: @"-", r.iosVersion ?: @"-", r.price ?: @"-",
         r.seller ?: @"-", r.link ?: @"-", r.note ?: @"-",
         r.capturedAt ?: @"-"];
    }
    [UIPasteboard generalPasteboard].string = m;
    return list.count;
}

#pragma mark - TXT 导出

+ (nullable NSString *)exportTXTWithRecords:(NSArray<AHRecord *> *)records {
    if (!records.count) return nil;
    NSMutableString *m = [NSMutableString string];
    [m appendString:@"========== 爱回收严选二手 批量查找导出 ==========\n"];
    [m appendFormat:@"导出时间: %@\n", [NSDate date]];
    [m appendFormat:@"记录数: %lu\n\n", (unsigned long)records.count];

    NSInteger i = 1;
    for (AHRecord *r in records) {
        [m appendFormat:@"---------- 记录 %ld ----------\n", (long)i++];
        [m appendString:[self _singleLine:r]];
        [m appendString:@"\n"];
    }

    NSString *path = [self _docPath:[NSString stringWithFormat:@"ah_yellow_export_%@.txt", [self _ts]]];
    NSError *err = nil;
    BOOL ok = [m writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    return ok ? path : nil;
}

#pragma mark - CSV（Excel 兼容）导出

+ (nullable NSString *)exportCSVWithRecords:(NSArray<AHRecord *> *)records {
    NSMutableString *m = [NSMutableString string];
    // UTF-8 BOM，让 Excel 正确识别中文
    [m appendString:@"\xEF\xBB\xBF"];
    [m appendString:@"型号,内存,颜色,电池,系统,价格,卖家,链接,备注,采集时间\n"];
    for (AHRecord *r in records) {
        [m appendFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%@,%@\n",
         [self _csvSafe:r.model], [self _csvSafe:r.memory], [self _csvSafe:r.color],
         [self _csvSafe:r.battery], [self _csvSafe:r.iosVersion], [self _csvSafe:r.price],
         [self _csvSafe:r.seller], [self _csvSafe:r.link], [self _csvSafe:r.note],
         [self _csvSafe:r.capturedAt]];
    }

    NSString *path = [self _docPath:[NSString stringWithFormat:@"ah_yellow_export_%@.csv", [self _ts]]];
    NSError *err = nil;
    BOOL ok = [m writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    return ok ? path : nil;
}

/// 转义 CSV 中的逗号、双引号与换行
+ (NSString *)_csvSafe:(NSString *)s {
    if (!s) return @"";
    if ([s containsString:@","] || [s containsString:@"\""] || [s containsString:@"\n"]) {
        return [NSString stringWithFormat:@"\"%@\"",
                [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
    }
    return s;
}

@end
