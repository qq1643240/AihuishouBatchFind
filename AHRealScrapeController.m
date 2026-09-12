//
//  AHRealScrapeController.m
//  AihuishouBatchFind
//

#import "AHRealScrapeController.h"
#import "AHCaptureEngine.h"
#import "AHRecordStore.h"
#import "AHExporter.h"
#import "AHProgressHUD.h"

@interface AHRealScrapeController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *modeSeg;

@property (nonatomic, assign) AHCaptureMode mode;
@property (nonatomic, assign) NSInteger maxPages;

@property (nonatomic, strong) NSArray<AHRecord *> *records;
@property (nonatomic, strong) NSMutableArray<AHRecord *> *selected;

@end


@implementation AHRealScrapeController

- (instancetype)init {
    if ((self = [super init])) {
        _mode = AHCaptureModeUI;
        _maxPages = 10;
        _records = @[];
        _selected = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"真实抓取";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(onClose)];
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

    [self refreshRecords];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;   // 0 模式  1 控制  2 统计  3 最近记录  4 数据操作
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"抓取模式";
        case 1: return @"控制";
        case 2: return @"实时统计";
        case 3: return [NSString stringWithFormat:@"最近抓取记录（显示前 %lu 条）",
                        (unsigned long)self.records.count];
        case 4: return @"数据操作";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;   // 开始/停止 + 页数
    if (section == 2) return 3;
    if (section == 3) return MAX(1, (NSInteger)self.records.count);
    if (section == 4) return 3;   // 复制选中 / 复制全部 / 清空
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    AHCaptureEngine *engine = [AHCaptureEngine shared];

    // ---- 0 模式 ----
    if (ip.section == 0) {
        UITableViewCell *cell = [self cell:@"modeCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.modeSeg) {
            self.modeSeg = [[UISegmentedControl alloc] initWithItems:@[@"界面抓取", @"网络嗅探"]];
            self.modeSeg.selectedSegmentIndex = (self.mode == AHCaptureModeUI) ? 0 : 1;
            [self.modeSeg addTarget:self action:@selector(onModeChanged:) forControlEvents:UIControlEventValueChanged];
        }
        self.modeSeg.frame = CGRectMake(0, 0, 200, 30);
        cell.accessoryView = self.modeSeg;
        cell.textLabel.text = @"模式";
        return cell;
    }

    // ---- 1 控制 ----
    if (ip.section == 1) {
        if (ip.row == 0) {
            UITableViewCell *cell = [self cell:@"btnCell"];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            if (self.mode == AHCaptureModeUI) {
                BOOL running = engine.autoScrollRunning;
                cell.textLabel.text = running ? @"⊙ 抓取中… 点击停止" : @"▶ 开始界面抓取（自动翻页）";
                cell.textLabel.textColor = running ? UIColor.systemOrangeColor : UIColor.systemBlueColor;
            } else {
                cell.textLabel.text = engine.sniffEnabled ? @"■ 停止网络监听" : @"▶ 开始网络监听";
                cell.textLabel.textColor = engine.sniffEnabled ? UIColor.systemRedColor : UIColor.systemBlueColor;
            }
            return cell;
        } else {
            // 页数
            UITableViewCell *cell = [self cell:@"stepperCell"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"抓取页数";
            UIStepper *st = [[UIStepper alloc] init];
            st.minimumValue = 1; st.maximumValue = 100; st.stepValue = 1;
            st.value = self.maxPages;
            st.tag = 900;
            [st addTarget:self action:@selector(onPagesChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = st;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 页", (long)self.maxPages];
            return cell;
        }
    }

    // ---- 2 统计 ----
    if (ip.section == 2) {
        UITableViewCell *cell = [self cell:@"statCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (ip.row == 0) {
            cell.textLabel.text = @"网络捕获请求";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)engine.sniffRequests];
        } else if (ip.row == 1) {
            cell.textLabel.text = @"JSON 提取入库";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条", (unsigned long)engine.sniffHits];
        } else {
            cell.textLabel.text = @"记录库总条数";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 条", (long)[[AHRecordStore sharedStore] count]];
        }
        return cell;
    }

    // ---- 3 最近记录 ----
    if (ip.section == 3) {
        UITableViewCell *cell = [self cell:@"recCell" style:UITableViewCellStyleSubtitle];
        if (self.records.count == 0) {
            cell.textLabel.text = @"暂无记录，先点上面的开始";
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.detailTextLabel.text = @"";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        AHRecord *r = self.records[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                               r.model ?: @"-", r.memory ?: @"-", r.color ?: @"-"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"电池%@ 系统%@ ¥%@ %@",
                                     r.battery ?: @"-", r.iosVersion ?: @"-",
                                     r.price ?: @"-", r.capturedAt ?: @""];
        cell.accessoryType = [self.selected containsObject:r] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

    // ---- 4 数据操作 ----
    UITableViewCell *cell = [self cell:@"btnCell"];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = UIColor.systemBlueColor;
    if (ip.row == 0) {
        cell.textLabel.text = @"复制选中记录";
    } else if (ip.row == 1) {
        cell.textLabel.text = @"复制全部记录";
    } else {
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.textLabel.text = @"清空记录库";
    }
    return cell;
}

#pragma mark - Cell helper

- (UITableViewCell *)cell:(NSString *)ident {
    return [self cell:ident style:UITableViewCellStyleValue1];
}

- (UITableViewCell *)cell:(NSString *)ident style:(UITableViewCellStyle)style {
    UITableViewCell *c = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:ident];
    c.textLabel.text = @"";
    c.detailTextLabel.text = @"";
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.textLabel.textColor = UIColor.labelColor;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

#pragma mark - 事件

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 1 && ip.row == 0) {
        if (self.mode == AHCaptureModeUI) [self toggleUIScrape];
        else                              [self toggleSniff];
        return;
    }
    if (ip.section == 3 && self.records.count) {
        AHRecord *r = self.records[ip.row];
        if ([self.selected containsObject:r]) [self.selected removeObject:r];
        else                                  [self.selected addObject:r];
        [tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }
    if (ip.section == 4) {
        if      (ip.row == 0) [self onCopySelected];
        else if (ip.row == 1) [self onCopyAll];
        else                  [self onClearAll];
    }
}

- (void)onModeChanged:(UISegmentedControl *)seg {
    self.mode = (seg.selectedSegmentIndex == 0) ? AHCaptureModeUI : AHCaptureModeNetwork;
    [self.tableView reloadData];
}

- (void)onPagesChanged:(UIStepper *)st {
    self.maxPages = (NSInteger)st.value;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)onClose {
    [[AHCaptureEngine shared] stopAutoScrollCapture];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 界面抓取

- (void)toggleUIScrape {
    AHCaptureEngine *e = [AHCaptureEngine shared];

    if (e.autoScrollRunning) {
        [e stopAutoScrollCapture];
        [self.tableView reloadData];
        return;
    }

    [AHProgressHUD showWithTitle:@"开始界面抓取"];
    [AHProgressHUD updateTitle:@"正在定位「严选二手」列表…" progress:0.02];

    __weak typeof(self) wself = self;
    NSInteger pages = self.maxPages;

    [e startAutoScrollCaptureMaxPages:pages
                             progress:^(NSInteger page, NSInteger totalSaved) {
        double p = (double)page / (double)pages;
        NSString *t = [NSString stringWithFormat:@"第 %ld/%ld 页 · 已入库 %ld 条",
                       (long)page, (long)pages, (long)totalSaved];
        [AHProgressHUD updateTitle:t progress:p];
    }
                           completion:^(NSInteger totalSaved) {
        [AHProgressHUD updateTitle:@"抓取完成，正在刷新…" progress:1.0];
        [wself refreshRecords];
        [AHProgressHUD dismiss];
        [wself toast:[NSString stringWithFormat:@"本次共入库 %ld 条真实记录", (long)totalSaved]];
    }];
}

#pragma mark - 网络嗅探

- (void)toggleSniff {
    AHCaptureEngine *e = [AHCaptureEngine shared];
    e.sniffEnabled = !e.sniffEnabled;

    if (e.sniffEnabled) {
        [self toast:@"已开启监听\n\n现在回到爱回收正常浏览「严选二手」列表，返回的真实数据会自动入库。\n抓完记得回来点停止。"];
        // 后台定时刷新统计
        [self startStatTimer];
    } else {
        [self stopStatTimer];
        [self refreshRecords];
        [self toast:[NSString stringWithFormat:@"已停止监听\n本次捕获 %lu 个请求，入库 %lu 条",
                     (unsigned long)e.sniffRequests, (unsigned long)e.sniffHits]];
    }
    [self.tableView reloadData];
}

static NSTimer *_statTimer = nil;

- (void)startStatTimer {
    [self stopStatTimer];
    __weak typeof(self) wself = self;
    _statTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
        [wself.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                       withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)stopStatTimer {
    if (_statTimer) { [_statTimer invalidate]; _statTimer = nil; }
}

#pragma mark - 数据操作

- (void)onCopySelected {
    if (!self.selected.count) { [self toast:@"请先在记录列表里点选"]; return; }
    [AHExporter copyAllRecords:self.selected];
    [self toast:[NSString stringWithFormat:@"已复制 %lu 条", (unsigned long)self.selected.count]];
}

- (void)onCopyAll {
    NSArray *all = [[AHRecordStore sharedStore] allRecords];
    if (!all.count) { [self toast:@"暂无记录"]; return; }
    NSInteger n = [AHExporter copyAllRecords:all];
    [self toast:[NSString stringWithFormat:@"已复制 %ld 条", (long)n]];
}

- (void)onClearAll {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空所有记录？"
                                                                 message:@"不可撤销"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[AHRecordStore sharedStore] deleteAll];
        [self refreshRecords];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)onExport {
    NSArray *all = [[AHRecordStore sharedStore] allRecords];
    if (!all.count) { [self toast:@"暂无可导出记录"]; return; }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"导出"
                                                                 message:[NSString stringWithFormat:@"共 %lu 条", (unsigned long)all.count]
                                                          preferredStyle:UIAlertControllerStyleActionSheet];

    [ac addAction:[UIAlertAction actionWithTitle:@"TXT 文本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *p = [AHExporter exportTXTWithRecords:all];
        [self showPath:p];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Excel (CSV)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *p = [AHExporter exportCSVWithRecords:all];
        [self showPath:p];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                             self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showPath:(NSString *)p {
    NSString *msg = p ? [NSString stringWithFormat:@"已保存到：\n%@", p] : @"导出失败";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"导出成功"
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 刷新

- (void)refreshRecords {
    NSArray *all = [[AHRecordStore sharedStore] allRecords];
    if (all.count > 50) all = [all subarrayWithRange:NSMakeRange(0, 50)];
    self.records = all;
    [self.selected removeAllObjects];
    [self.tableView reloadData];
}

- (void)toast:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:msg
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)dealloc {
    [self stopStatTimer];
}

@end
