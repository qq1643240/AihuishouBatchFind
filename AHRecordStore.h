// AHRecordStore.h
// SQLite 仓库 —— 单条记录结构与 CRUD 操作。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AHRecord : NSObject
@property (nonatomic, assign) int64_t rowId;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *memory;
@property (nonatomic, copy, nullable) NSString *color;
@property (nonatomic, copy, nullable) NSString *battery;
@property (nonatomic, copy, nullable) NSString *iosVersion;
@property (nonatomic, copy, nullable) NSString *price;
@property (nonatomic, copy, nullable) NSString *seller;
@property (nonatomic, copy, nullable) NSString *link;
@property (nonatomic, copy, nullable) NSString *note;
@property (nonatomic, copy, nullable) NSString *capturedAt;   // yyyy-MM-dd HH:mm:ss
@end


@interface AHRecordStore : NSObject

+ (instancetype)sharedStore;

/// 打开 / 创建数据库（默认 Documents/ahbatchfind.sqlite）
- (BOOL)open;

/// 插入 / 保存一条记录
- (BOOL)insertRecord:(AHRecord *)r;

/// 全部记录
- (NSArray<AHRecord *> *)allRecords;

/// 按筛选条件查询（任一字段为 nil/空 表示不限定；其余字段走 LIKE 匹配）
- (NSArray<AHRecord *> *)queryRecordsWithModel:(nullable NSString *)m
                                        memory:(nullable NSString *)mem
                                         color:(nullable NSString *)c
                                       battery:(nullable NSString *)b
                                    iosVersion:(nullable NSString *)iv;

/// 清空表
- (BOOL)deleteAll;

/// 总条数
- (NSInteger)count;

@end

NS_ASSUME_NONNULL_END
