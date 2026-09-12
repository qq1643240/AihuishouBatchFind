// AHExporter.h
// 导出 & 复制工具：TXT 文本 / Excel 兼容 CSV（含 UTF-8 BOM，可直接 Excel/WPS 打开）
// 单条复制 / 批量复制

#import <Foundation/Foundation.h>
#import "AHRecordStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface AHExporter : NSObject

#pragma mark - 复制到系统剪贴板

/// 复制单条记录（多行可读文本）
+ (void)copySingleRecord:(AHRecord *)r;

/// 复制指定列表，nil 则导出全部
+ (NSInteger)copyAllRecords:(nullable NSArray<AHRecord *> *)records;

#pragma mark - 导出文件

/// 导出为 TXT 文件，返回文件路径（Documents 目录）
+ (nullable NSString *)exportTXTWithRecords:(NSArray<AHRecord *> *)records;

/// 导出为 CSV 文件，UTF-8 + BOM，Excel/WPS 直接打开
+ (nullable NSString *)exportCSVWithRecords:(NSArray<AHRecord *> *)records;

@end

NS_ASSUME_NONNULL_END
