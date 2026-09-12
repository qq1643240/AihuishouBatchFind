// AHBatchFindController.m
#import "AHBatchFindController.h"
#import "AHRecordStore.h"
#import "AHExporter.h"
#import "AHProgressHUD.h"
#import "AHBatchFindProxy.h"

typedef NS_ENUM(NSInteger, AHBFState) {
    AHBFS_Idle    = 0,
    AHBFS_Running = 1,
    AHBFS_Done    = 2,
};

@interface AHBatchFindController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

// 数据
@property (nonatomic, strong) NSMutableArray<AHRecord *> *records;
@property (nonatomic, strong) NSMutableArray<AHRecord *> *selected;   // 多选 copy

// 筛选
@property (nonatomic, strong) NSMutableDictionary *filter;
@property (nonatomic, copy)   NSArray<NSString *> *memoryOptions;
@property (nonatomic, copy)   NSArray<NSString *> *iosOptions;
@property (nonatomic, copy)   NSArray<NSString *> *colorOptions;

// 状态
@property (nonatomic, assign) AHBFState state;

@end


@implementation AHBatchFindController

- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSMutableArray array];
        _selected = [NSMutableArray array];
        _filter   = [NSMutableDictionary dictionary];
        _state    = AHBFS_Idle;

        _memoryOptions = @[@"不限", @"64GB", @"128GB", @"256GB", @"512GB", @"1TB"];
        _iosOptions    = @[@"不限", @"iOS 15", @"iOS 16", @"iOS 17", @"iOS 18"];
        _colorOptions  = @[@"不限", @"黑色", @"白色", @"蓝色", @"原色",
                            @"钛金属色", @"暗紫色", @"银色", @"金色", @"星光色"];
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"批量查找";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self action:@selector(onClose)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"导出 ▼"
                                          style:UIBarButtonItemStylePlain
                                         target:self
                                         action:@selector(onExport)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate   = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                      UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    [self refreshFromDB];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;   // 0 筛选  1 操作  2 记录  3 复制/导出
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"筛选条件";
        case 1: return @"操作";
        case 2: return [NSString stringWithFormat:@"结果 / 记录库（当前显示 %lu 条）",
                             (unsigned long)self.records.count];
        case 3: return @"复制 & 导出";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5;     // 型号/内存/电池/版本/颜色
    if (section == 1) return 2;     // 开始 / 清空
    if (section == 2) return MAX(1, (NSInteger)self.records.count);  // 空记录提示 1 行
    if (section == 3) return 3;     // 复制单条 / 复制全部 / 导出
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    // ============ 0 筛选 ============
    if (ip.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                  reuseIdentifier:@"row"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = [self _accessoryForRow:ip.row forCell:cell];
        cell.textLabel.font   = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];

        switch (ip.row) {
            case 0: cell.textLabel.text = @"机器型号"; cell.detailTextLabel.text = self.filter[@"model"]   ?: @""; break;
            case 1: cell.textLabel.text = @"内存";     cell.detailTextLabel.text = self.filter[@"memory"]  ?: @"不限"; break;
            case 2: cell.textLabel.text = @"电池状态"; cell.detailTextLabel.text = self.filter[@"battery"]  ?: @""; break;
            case 3: cell.textLabel.text = @"系统版本"; cell.detailTextLabel.text = self.filter[@"ios"]      ?: @"不限"; break;
            case 4: cell.textLabel.text = @"颜色";     cell.detailTextLabel.text = self.filter[@"color"]   ?: @"不限"; break;
        }
        return cell;
    }

    // ============ 1 操作 ============
    if (ip.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"btn"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  reuseIdentifier:@"btn"];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        if (ip.row == 0) {
            cell.textLabel.textColor = UIColor.systemBlueColor;
            cell.textLabel.text = (self.state == AHBFS_Running)
                ? @"⊙ 运行中... 请稍候"
                : @"▶ 开始批量查找";
        } else {
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.textLabel.text = @"清空全部记录";
        }
        return cell;
    }

    // ============ 2 记录列表 ============
    if (ip.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rec"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                  reuseIdentifier:@"rec"];

        if (self.records.count == 0) {
            cell.textLabel.text = @"暂无记录，请先设置筛选并点击开始";
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.detailTextLabel.text = @"";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        AHRecord *r = self.records[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                               r.model ?: @"-", r.memory ?: @"-", r.color ?: @"-"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"电池 %@   系统 %@   ¥%@   采集 %@",
                                     r.battery ?: @"-",
                                     r.iosVersion ?: @"-",
                                     r.price ?: @"-",
                                     r.capturedAt ?: @"-"];
        cell.accessoryType = [self.selected containsObject:r]
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
        return cell;
    }

    // ============ 3 复制 & 导出 ============
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"btn"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"btn"];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = UIColor.systemBlueColor;
    switch (ip.row) {
        case 0: cell.textLabel.text = @"复制当前选中（先在结果列表里点选）"; break;
        case 1: cell.textLabel.text = @"复制全部记录"; break;
        case 2: cell.textLabel.text = @"导出全部为 TXT / Excel (CSV)"; break;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 1) {
        if (ip.row == 0) [self onStart];
        else              [self onClearAll];
        return;
    }

    if (ip.section == 2 && self.records.count) {
        AHRecord *r = self.records[ip.row];
        if ([self.selected containsObject:r]) [self.selected removeObject:r];
        else                                  [self.selected addObject:r];
        [tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }

    if (ip.section == 3) {
        if      (ip.row == 0) [self onCopySingle];
        else if (ip.row == 1) [self onCopyAll];
        else                  [self onExport];
    }
}

#pragma mark - Filter UI

- (UIView *)_accessoryForRow:(NSInteger)row forCell:(UITableViewCell *)cell {
    if (row == 0) {   // 型号：文本输入
        UITextField *tf = [UITextField new];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.placeholder = @"如 iPhone 15 Pro Max";
        tf.text = self.filter[@"model"] ?: @"";
        tf.font = [UIFont systemFontOfSize:14];
        tf.frame = CGRectMake(0, 0, 200, 32);
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.tag = 100;
        [tf addTarget:self action:@selector(_filterTextChanged:) forControlEvents:UIControlEventEditingChanged];
        return tf;
    }
    if (row == 2) {   // 电池：文本输入，支持 >=90、95%
        UITextField *tf = [UITextField new];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.placeholder = @"如 >=90";
        tf.text = self.filter[@"battery"] ?: @"";
        tf.font = [UIFont systemFontOfSize:14];
        tf.frame = CGRectMake(0, 0, 120, 32);
        tf.tag = 101;
        [tf addTarget:self action:@selector(_filterTextChanged:) forControlEvents:UIControlEventEditingChanged];
        return tf;
    }
    // 内存 / 系统 / 颜色：弹出 ActionSheet
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, 110, 32);
    btn.titleLabel.font = [UIFont systemFontOfSize:14];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;

    NSString *cur = @"不限";
    NSInteger tag = 0;
    if (row == 1) { cur = self.filter[@"memory"] ?: @"不限"; tag = 200; }
    if (row == 3) { cur = self.filter[@"ios"]    ?: @"不限"; tag = 201; }
    if (row == 4) { cur = self.filter[@"color"]  ?: @"不限"; tag = 202; }

    [btn setTitle:cur forState:UIControlStateNormal];
    btn.tag = tag;
    [btn addTarget:self action:@selector(_onPickOption:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)_filterTextChanged:(UITextField *)tf {
    if (tf.tag == 100) self.filter[@"model"]   = tf.text;
    if (tf.tag == 101) self.filter[@"battery"] = tf.text;
}

- (void)_onPickOption:(UIButton *)btn {
    NSArray<NSString *> *opts = nil;
    NSString *key = nil;
    if (btn.tag == 200) { opts = self.memoryOptions; key = @"memory"; }
    if (btn.tag == 201) { opts = self.iosOptions;    key = @"ios"; }
    if (btn.tag == 202) { opts = self.colorOptions;  key = @"color"; }
    if (!opts || !key) return;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"请选择"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *opt in opts) {
        [ac addAction:[UIAlertAction actionWithTitle:opt
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *a) {
            self.filter[key] = opt;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationFade];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = btn;
    ac.popoverPresentationController.sourceRect = btn.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Actions

- (void)onClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onClearAll {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空所有记录？"
                                                                  message:@"该操作不可撤销。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *a) {
        [[AHRecordStore sharedStore] deleteAll];
        [self refreshFromDB];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)onCopySingle {
    if (!self.selected.count) {
        [self _toast:@"请先在结果列表里点选至少 1 条"];
        return;
    }
    AHRecord *r = self.selected.firstObject;
    [AHExporter copySingleRecord:r];
    [self _toast:@"已复制 1 条记录到剪贴板"];
}

- (void)onCopyAll {
    NSArray<AHRecord *> *items = self.selected.count ? self.selected : self.records;
    if (!items.count) { [self _toast:@"暂无记录"]; return; }
    NSInteger n = [AHExporter copyAllRecords:items];
    [self _toast:[NSString stringWithFormat:@"已复制 %ld 条记录（Tab 分隔，可直接粘贴到 Excel）", (long)n]];
}

- (void)onExport {
    NSArray<AHRecord *> *items = self.records;
    if (!items.count) { [self _toast:@"暂无可导出的记录"]; return; }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"导出"
                                                                  message:[NSString stringWithFormat:@"共 %lu 条", (unsigned long)items.count]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"TXT 文本"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *a) {
        NSString *p = [AHExporter exportTXTWithRecords:items];
        [self _showExportResult:p ext:@"txt"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Excel (CSV)"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *a) {
        NSString *p = [AHExporter exportCSVWithRecords:items];
        [self _showExportResult:p ext:@"csv"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                              self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)_showExportResult:(NSString *)path ext:(NSString *)ext {
    NSString *msg = path
        ? [NSString stringWithFormat:@"已保存到：\n%@\n\n可用 Filza 打开，或 AirDrop 到 Mac/Windows", path]
        : @"导出失败，请检查 Documents 目录权限";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"导出成功"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 批量查找主流程

- (void)onStart {
    if (self.state == AHBFS_Running) return;

    NSString *model   = self.filter[@"model"]   ?: @"";
    NSString *memory  = self.filter[@"memory"]  ?: @"不限";
    NSString *color   = self.filter[@"color"]   ?: @"不限";
    NSString *battery = self.filter[@"battery"] ?: @"";
    NSString *ios     = self.filter[@"ios"]     ?: @"不限";

    if (!model.length) {
        [self _toast:@"请先填写机器型号"];
        return;
    }

    self.state = AHBFS_Running;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationNone];

    // ① 明确的「开始」提示
    [AHProgressHUD showWithTitle:[NSString stringWithFormat:@"开始查找：%@", model]];
    [AHProgressHUD updateTitle:@"正在向爱回收严选二手发起请求..." progress:0.05];

    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // ② 进行中：实时更新标题 & 进度
        [wself _runBatchSearchWithModel:model memory:memory color:color battery:battery iosVersion:ios];
    });
}

// =============================================================================
// ⚠️ 关键：这里实现实际的批量查询逻辑 ⚠️
//
// 爱回收 App 内部的搜索接口 /scheme /searchViewController 类名并未公开。
// 默认的 _runBatchSearchWithModel:... 是一个示例实现，仅演示完整流程：
//   - 多页循环
//   - 每页 sleep 模拟网络延时
//   - 实时更新 HUD 标题/进度
//   - 直接 insertRecord 入库
//
// 投产前你需要根据实际抓包或 class-dump 把内部字段填上。
// =============================================================================

- (void)_runBatchSearchWithModel:(NSString *)model
                          memory:(NSString *)memory
                           color:(NSString *)color
                         battery:(NSString *)battery
                        iosVersion:(NSString *)ios {

    int totalPages = 5;
    AHRecordStore *store = [AHRecordStore sharedStore];

    for (int page = 1; page <= totalPages; page++) {

        // ---------- 真实环境请替换此段 ----------
        // 示例：每页生成 8 条记录，按筛选条件做最小填充
        int perPage = 8;
        for (int i = 0; i < perPage; i++) {
            AHRecord *r = [AHRecord new];
            r.model       = model;
            r.memory      = [memory isEqualToString:@"不限"] ? @"256GB" : memory;
            r.color       = [color  isEqualToString:@"不限"]
                            ? (arc4random_uniform(2) ? @"黑色" : @"钛金属色")
                            : color;
            r.battery     = [NSString stringWithFormat:@"%d%%", 90 + arc4random_uniform(10)];
            r.iosVersion  = [ios    isEqualToString:@"不限"] ? @"17.3.1" : ios;
            r.price       = [NSString stringWithFormat:@"%d", 4500 + (int)arc4random_uniform(2000)];
            r.seller      = [NSString stringWithFormat:@"严选商家%d", (int)arc4random_uniform(99) + 1];
            r.link        = @"https://www.aihuishou.com/...";
            r.note        = @"";
            r.capturedAt  = nil;   // DB 自动填充
            [store insertRecord:r];
        }
        // ---------------------------------------

        double prog = (double)page / totalPages;
        NSString *detail = [NSString stringWithFormat:@"第 %d/%d 页 · 已采集 %ld 条",
                            page, totalPages, (long)[store count]];
        [AHProgressHUD updateTitle:detail progress:prog];

        [NSThread sleepForTimeInterval:0.4];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [AHProgressHUD updateTitle:@"采集完成，正在刷新结果..." progress:1.0];
        [self refreshFromDB];
        [AHProgressHUD dismiss];
        self.state = AHBFS_Done;
        [self _toast:[NSString stringWithFormat:@"批量查找完成，共 %lu 条",
                       (unsigned long)self.records.count]];
    });
}

#pragma mark - Helpers

- (void)refreshFromDB {
    NSArray *rows = [[AHRecordStore sharedStore]
                     queryRecordsWithModel:self.filter[@"model"]   ?: @""
                                   memory:self.filter[@"memory"]  ?: @""
                                    color:self.filter[@"color"]   ?: @""
                                  battery:self.filter[@"battery"] ?: @""
                               iosVersion:self.filter[@"ios"]     ?: @""];
    self.records = [rows mutableCopy];
    [self.tableView reloadData];
}

- (void)_toast:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:msg
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
