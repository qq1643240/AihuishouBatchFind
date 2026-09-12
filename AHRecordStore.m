// AHRecordStore.m
#import "AHRecordStore.h"
#import <sqlite3.h>

static NSString *const kDBName = @"ahbatchfind.sqlite";

@implementation AHRecord

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ | %@ | %@ | %@ | %@ | ¥%@",
            self.model ?: @"-", self.memory ?: @"-", self.color ?: @"-",
            self.battery ?: @"-", self.iosVersion ?: @"-", self.price ?: @"-"];
}

@end


@interface AHRecordStore () {
    sqlite3 *_db;
}
@end

@implementation AHRecordStore

+ (instancetype)sharedStore {
    static AHRecordStore *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[AHRecordStore alloc] init];
        [s_instance open];
    });
    return s_instance;
}

#pragma mark - Path / Open

- (NSString *)_dbPath {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    // 注意：tweak 注入到爱回收 App，写入该 App 的 Documents 目录。
    //      若希望跨 App 共享或在卸载后保留，请改用 App Group。
    return [dir stringByAppendingPathComponent:kDBName];
}

- (BOOL)open {
    if (_db) return YES;

    NSString *path = [self _dbPath];
    int rc = sqlite3_open(path.UTF8String, &_db);
    if (rc != SQLITE_OK) return NO;

    const char *sql =
    "CREATE TABLE IF NOT EXISTS records ("
    "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  model         TEXT,"
    "  memory        TEXT,"
    "  color         TEXT,"
    "  battery       TEXT,"
    "  ios_version   TEXT,"
    "  price         TEXT,"
    "  seller        TEXT,"
    "  link          TEXT,"
    "  note          TEXT,"
    "  captured_at   TEXT DEFAULT (datetime('now','localtime'))"
    ");";

    char *err = NULL;
    if (sqlite3_exec(_db, sql, NULL, NULL, &err) != SQLITE_OK) {
        if (err) sqlite3_free(err);
        return NO;
    }
    return YES;
}

#pragma mark - Insert

- (BOOL)insertRecord:(AHRecord *)r {
    if (!_db && ![self open]) return NO;

    const char *sql =
    "INSERT INTO records (model, memory, color, battery, ios_version,"
    " price, seller, link, note, captured_at) "
    "VALUES (?,?,?,?,?,?,?,?,?,?);";

    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &st, NULL) != SQLITE_OK) return NO;

    sqlite3_bind_text(st, 1, [r.model       UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, [r.memory      UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 3, [r.color       UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 4, [r.battery     UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 5, [r.iosVersion  UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 6, [r.price       UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 7, [r.seller      UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 8, [r.link        UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 9, [r.note        UTF8String] ?: "", -1, SQLITE_TRANSIENT);

    NSString *ts = r.capturedAt ?: [self _nowString];
    sqlite3_bind_text(st, 10, [ts UTF8String], -1, SQLITE_TRANSIENT);

    BOOL ok = (sqlite3_step(st) == SQLITE_DONE);
    sqlite3_finalize(st);
    return ok;
}

#pragma mark - Query

- (NSArray<AHRecord *> *)allRecords {
    return [self queryRecordsWithModel:nil memory:nil color:nil battery:nil iosVersion:nil];
}

- (NSArray<AHRecord *> *)queryRecordsWithModel:(NSString *)m
                                       memory:(NSString *)mem
                                         color:(NSString *)c
                                       battery:(NSString *)b
                                    iosVersion:(NSString *)iv {
    if (!_db && ![self open]) return @[];

    NSMutableString *sql = [@"SELECT id, model, memory, color, battery, ios_version,"
                            " price, seller, link, note, captured_at FROM records" mutableCopy];
    NSMutableArray *conds = [NSMutableArray array];
    if (m.length)    [conds addObject:@"model LIKE ?"];
    if (mem.length)  [conds addObject:@"memory LIKE ?"];
    if (c.length)    [conds addObject:@"color LIKE ?"];
    if (b.length)    [conds addObject:@"battery LIKE ?"];
    if (iv.length)   [conds addObject:@"ios_version LIKE ?"];
    if (conds.count) [sql appendFormat:@" WHERE %@", [conds componentsJoinedByString:@" AND "]];
    [sql appendString:@" ORDER BY id DESC"];

    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) return @[];

    int idx = 1;
    if (m.length)    sqlite3_bind_text(st, idx++, [[NSString stringWithFormat:@"%%%@%%", m] UTF8String], -1, SQLITE_TRANSIENT);
    if (mem.length)  sqlite3_bind_text(st, idx++, [[NSString stringWithFormat:@"%%%@%%", mem] UTF8String], -1, SQLITE_TRANSIENT);
    if (c.length)    sqlite3_bind_text(st, idx++, [[NSString stringWithFormat:@"%%%@%%", c] UTF8String], -1, SQLITE_TRANSIENT);
    if (b.length)    sqlite3_bind_text(st, idx++, [[NSString stringWithFormat:@"%%%@%%", b] UTF8String], -1, SQLITE_TRANSIENT);
    if (iv.length)   sqlite3_bind_text(st, idx++, [[NSString stringWithFormat:@"%%%@%%", iv] UTF8String], -1, SQLITE_TRANSIENT);

    NSMutableArray<AHRecord *> *out = [NSMutableArray array];
    while (sqlite3_step(st) == SQLITE_ROW) {
        AHRecord *r = [AHRecord new];
        r.rowId = sqlite3_column_int64(st, 0);

#define BIND_STR(outKey, colIdx) \
    if (sqlite3_column_type(st, colIdx) == SQLITE_TEXT) { \
        const unsigned char *t = sqlite3_column_text(st, colIdx); \
        if (t) r.outKey = [NSString stringWithUTF8String:(const char *)t]; \
    }

        BIND_STR(model,       1)
        BIND_STR(memory,      2)
        BIND_STR(color,       3)
        BIND_STR(battery,     4)
        BIND_STR(iosVersion,  5)
        BIND_STR(price,       6)
        BIND_STR(seller,      7)
        BIND_STR(link,        8)
        BIND_STR(note,        9)
        BIND_STR(capturedAt, 10)
#undef BIND_STR

        [out addObject:r];
    }
    sqlite3_finalize(st);
    return out;
}

#pragma mark - Misc

- (BOOL)deleteAll {
    if (!_db) return NO;
    char *err = NULL;
    BOOL ok = (sqlite3_exec(_db, "DELETE FROM records;", NULL, NULL, &err) == SQLITE_OK);
    if (err) sqlite3_free(err);
    return ok;
}

- (NSInteger)count {
    if (!_db && ![self open]) return 0;
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "SELECT count(*) FROM records;", -1, &st, NULL) != SQLITE_OK) return 0;
    NSInteger n = 0;
    if (sqlite3_step(st) == SQLITE_ROW) n = sqlite3_column_int64(st, 0);
    sqlite3_finalize(st);
    return n;
}

- (NSString *)_nowString {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate date]];
}

@end
