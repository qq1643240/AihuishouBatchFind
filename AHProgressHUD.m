// AHProgressHUD.m
#import "AHProgressHUD.h"

#pragma mark - Internal View

@interface AHProgressHUDView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIProgressView *bar;
@end

@implementation AHProgressHUDView

- (instancetype)init {
    self = [super init];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        self.layer.cornerRadius = 12;

        _titleLabel = [UILabel new];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont boldSystemFontOfSize:16];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _detailLabel = [UILabel new];
        _detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        _detailLabel.font = [UIFont systemFontOfSize:13];
        _detailLabel.textAlignment = NSTextAlignmentCenter;
        _detailLabel.numberOfLines = 0;
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _bar.progressTintColor = [UIColor systemGreenColor];
        _bar.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_titleLabel];
        [self addSubview:_bar];
        [self addSubview:_detailLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor      constraintEqualToAnchor:self.topAnchor      constant:18],
            [_titleLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor  constant:16],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

            [_bar.topAnchor            constraintEqualToAnchor:_titleLabel.bottomAnchor constant:14],
            [_bar.leadingAnchor        constraintEqualToAnchor:self.leadingAnchor     constant:16],
            [_bar.trailingAnchor       constraintEqualToAnchor:self.trailingAnchor    constant:-16],

            [_detailLabel.topAnchor      constraintEqualToAnchor:_bar.bottomAnchor     constant:10],
            [_detailLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor   constant:16],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor  constant:-16],
            [_detailLabel.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor    constant:-16],
        ]];
    }
    return self;
}

@end


#pragma mark - Public

@implementation AHProgressHUD

static UIWindow *_window = nil;
static AHProgressHUDView *_view = nil;

+ (void)showWithTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_window) { [self _dismissSync]; }

        _window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        _window.windowLevel = UIWindowLevelAlert + 1;
        _window.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = UIColor.clearColor;
        _window.rootViewController = vc;
        _window.hidden = NO;

        _view = [[AHProgressHUDView alloc] init];
        _view.translatesAutoresizingMaskIntoConstraints = NO;
        _view.titleLabel.text = title ?: @"处理中...";
        _view.detailLabel.text = @"0% · 准备开始";
        _view.bar.progress = 0;
        [vc.view addSubview:_view];

        [NSLayoutConstraint activateConstraints:@[
            [_view.centerXAnchor      constraintEqualToAnchor:vc.view.centerXAnchor],
            [_view.centerYAnchor      constraintEqualToAnchor:vc.view.centerYAnchor],
            [_view.widthAnchor        constraintLessThanOrEqualToConstant:300],
        ]];
    });
}

+ (void)updateTitle:(NSString *)title progress:(double)p {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_view) return;
        if (title.length) _view.titleLabel.text = title;
        _view.bar.progress = (float)MAX(0.0, MIN(1.0, p));
        _view.detailLabel.text = [NSString stringWithFormat:@"%.0f%% · 正在处理...", p * 100];
    });
}

+ (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _dismissSync];
    });
}

+ (void)_dismissSync {
    _view = nil;
    _window.hidden = YES;
    _window = nil;
}

@end
