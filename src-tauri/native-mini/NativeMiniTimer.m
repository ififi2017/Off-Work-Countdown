#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <pwd.h>
#include <unistd.h>

static const NSSize OWCPanelSize = {228.0, 70.0};

@interface OWCMiniPanel : NSPanel
@end

@implementation OWCMiniPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface OWCNativeProgressView : NSView
@property(nonatomic, strong) CALayer *fillLayer;
@property(nonatomic) CGFloat progress;
- (void)setProgressValue:(double)value;
@end

@implementation OWCNativeProgressView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 2.0;
        self.layer.masksToBounds = YES;
        _fillLayer = [CALayer layer];
        _fillLayer.cornerRadius = 2.0;
        [self.layer addSublayer:_fillLayer];
        [self updateColors];
    }
    return self;
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.fillLayer.frame = NSMakeRect(
        0.0,
        0.0,
        self.bounds.size.width * self.progress,
        self.bounds.size.height
    );
    [CATransaction commit];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateColors];
}

- (void)setProgressValue:(double)value {
    self.progress = MIN(1.0, MAX(0.0, value));
    self.needsLayout = YES;
}

- (void)updateColors {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = [[NSColor separatorColor] colorWithAlphaComponent:0.28].CGColor;
        self.fillLayer.backgroundColor = [NSColor systemOrangeColor].CGColor;
    }];
}
@end

@interface OWCMiniContentView : NSView
@property(nonatomic, strong) NSTextField *timerLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSTextField *salaryLabel;
@property(nonatomic, strong) OWCNativeProgressView *progressView;
@property(nonatomic, strong) NSButton *salaryToggleButton;
@property(nonatomic) BOOL countdownRunning;
@property(nonatomic) BOOL salaryHidden;
@property(nonatomic) BOOL hasSalary;
/// 眼睛按钮的无障碍描述，由 Rust 按当前界面语言传下来。两个都存着，
/// 因为点击时会先本地翻转状态，等下一次 tick 再拿新文案就慢了一拍。
@property(nonatomic, copy) NSString *showEarningsLabel;
@property(nonatomic, copy) NSString *hideEarningsLabel;
- (void)updateTime:(NSString *)time
           percent:(NSString *)percent
            salary:(NSString *)salary
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText
        showSalary:(BOOL)showSalary
      salaryHidden:(BOOL)salaryHidden
 showEarningsLabel:(NSString *)showEarningsLabel
 hideEarningsLabel:(NSString *)hideEarningsLabel;
- (void)toggleSalaryVisibility;
@end

@implementation OWCMiniContentView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _timerLabel = [NSTextField labelWithString:@"--:--:--"];
        _timerLabel.font = [NSFont monospacedDigitSystemFontOfSize:27.0 weight:NSFontWeightSemibold];
        _timerLabel.textColor = [NSColor labelColor];
        _timerLabel.lineBreakMode = NSLineBreakByClipping;
        _timerLabel.maximumNumberOfLines = 1;

        // 百分比是次要信息：进度条已经把它表达过一遍，这里只作精确读数。
        // 用等宽数字，否则每秒刷新时右对齐文本的左边缘会随字宽变化而抖动。
        _detailLabel = [NSTextField labelWithString:@""];
        _detailLabel.font = [NSFont monospacedDigitSystemFontOfSize:10.0
                                                             weight:NSFontWeightMedium];
        _detailLabel.textColor = [NSColor tertiaryLabelColor];
        _detailLabel.alignment = NSTextAlignmentRight;
        _detailLabel.lineBreakMode = NSLineBreakByClipping;

        // 金额是右侧的主信息，字号与颜色都要压过百分比一档。
        _salaryLabel = [NSTextField labelWithString:@""];
        _salaryLabel.font = [NSFont monospacedDigitSystemFontOfSize:13.0
                                                             weight:NSFontWeightSemibold];
        _salaryLabel.textColor = [NSColor labelColor];
        _salaryLabel.alignment = NSTextAlignmentRight;
        _salaryLabel.lineBreakMode = NSLineBreakByClipping;

        _progressView = [[OWCNativeProgressView alloc] initWithFrame:NSZeroRect];

        _salaryToggleButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        _salaryToggleButton.bezelStyle = NSBezelStyleSmallSquare;
        _salaryToggleButton.bordered = NO;
        _salaryToggleButton.target = self;
        _salaryToggleButton.action = @selector(toggleSalaryVisibility);
        _salaryToggleButton.hidden = YES;

        [self addSubview:_timerLabel];
        [self addSubview:_detailLabel];
        [self addSubview:_salaryLabel];
        [self addSubview:_progressView];
        [self addSubview:_salaryToggleButton];
    }
    return self;
}

- (void)layout {
    [super layout];

    // 所有横向位置都从右边缘往左推导，只有一处真相来源。
    // 旧实现把右侧文字块和眼睛按钮各自独立定位，两者的边界恰好相等，
    // 结果是文字紧贴按钮（间距 0），并且 timerLabel 的 MAX() 兜底一旦生效
    // 就会盖住右侧内容——因为右侧位置仍按未兜底的宽度计算。
    const CGFloat inset = 16.0;
    const CGFloat buttonSize = 18.0;
    const CGFloat buttonGap = 8.0;
    const CGFloat columnGap = 12.0;
    const CGFloat width = self.bounds.size.width;
    const CGFloat contentRight = width - inset;

    self.progressView.frame = NSMakeRect(inset, 10.0, width - inset * 2.0, 3.0);

    if (!self.countdownRunning) {
        self.detailLabel.hidden = YES;
        self.salaryLabel.hidden = YES;
        self.salaryToggleButton.hidden = YES;
        // 空闲文案在 19 种语言下长度差异很大（"计时未开始" 五个字符，
        // 而德语 / 印地语要长得多），同样按可用宽度收缩，避免被裁切。
        const CGFloat idleWidth = width - inset * 2.0;
        self.timerLabel.alignment = NSTextAlignmentCenter;
        self.timerLabel.font = [self idleFontFittingWidth:idleWidth];
        self.timerLabel.frame = NSMakeRect(inset, 30.0, idleWidth, 22.0);
        return;
    }

    self.detailLabel.hidden = NO;

    const BOOL showsSalary = self.hasSalary && !self.salaryHidden;
    // 两行块的垂直中心；单行时也用它，保证切换隐藏前后按钮不跳动。
    const CGFloat blockCenterY = 43.0;

    const CGFloat buttonSlot = self.hasSalary ? buttonSize + buttonGap : 0.0;
    const CGFloat rightWidth = showsSalary ? 64.0 : 36.0;
    const CGFloat rightX = contentRight - buttonSlot - rightWidth;

    if (self.hasSalary) {
        self.salaryToggleButton.hidden = NO;
        self.salaryToggleButton.frame = NSMakeRect(
            contentRight - buttonSize,
            blockCenterY - buttonSize / 2.0,
            buttonSize,
            buttonSize
        );
    } else {
        self.salaryToggleButton.hidden = YES;
    }

    self.detailLabel.alignment = NSTextAlignmentRight;
    self.salaryLabel.hidden = !showsSalary;

    if (showsSalary) {
        // 金额在上（主信息），百分比在下（次要），整体围绕 blockCenterY 排布。
        self.salaryLabel.frame = NSMakeRect(rightX, blockCenterY - 1.0, rightWidth, 17.0);
        self.detailLabel.frame = NSMakeRect(rightX, blockCenterY - 15.0, rightWidth, 13.0);
    } else {
        self.detailLabel.frame = NSMakeRect(rightX, blockCenterY - 7.0, rightWidth, 13.0);
    }

    // 时间占据剩下的全部宽度，因此永远不会与右侧块重叠。
    const CGFloat leftWidth = MAX(1.0, rightX - columnGap - inset);
    self.timerLabel.alignment = NSTextAlignmentLeft;
    self.timerLabel.font = [self timerFontFittingWidth:leftWidth];
    self.timerLabel.frame = NSMakeRect(inset, blockCenterY - 16.0, leftWidth, 32.0);
}

/// 选出能在给定宽度内放下当前时间字符串的最大字号。
///
/// 时间的位数会变：「9:59:59」七位，跨十小时的班次是「12:59:59」八位，
/// 而显示薪资时左栏只剩九十多点。标签的 lineBreakMode 是 Clipping，
/// 放不下时会**静默截断**——原实现固定 27pt，长班次开头几小时会缺字符。
- (NSFont *)timerFontFittingWidth:(CGFloat)available {
    static const CGFloat candidates[] = {27.0, 25.0, 23.0, 21.0, 19.0};
    NSString *text = self.timerLabel.stringValue ?: @"";
    NSFont *font = nil;

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        font = [NSFont monospacedDigitSystemFontOfSize:candidates[i]
                                                weight:NSFontWeightSemibold];
        CGFloat needed = [text sizeWithAttributes:@{NSFontAttributeName: font}].width;
        if (needed <= available) return font;
    }
    return font;
}

/// 空闲文案的自适应字号。文案是词句而非数字，用常规系统字体。
- (NSFont *)idleFontFittingWidth:(CGFloat)available {
    static const CGFloat candidates[] = {15.0, 14.0, 13.0, 12.0, 11.0};
    NSString *text = self.timerLabel.stringValue ?: @"";
    NSFont *font = nil;

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        font = [NSFont systemFontOfSize:candidates[i] weight:NSFontWeightSemibold];
        CGFloat needed = [text sizeWithAttributes:@{NSFontAttributeName: font}].width;
        if (needed <= available) return font;
    }
    return font;
}

- (void)updateTime:(NSString *)time
           percent:(NSString *)percent
            salary:(NSString *)salary
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText
        showSalary:(BOOL)showSalary
      salaryHidden:(BOOL)salaryHidden
 showEarningsLabel:(NSString *)showEarningsLabel
 hideEarningsLabel:(NSString *)hideEarningsLabel {
    self.countdownRunning = running;
    self.hasSalary = showSalary;
    self.salaryHidden = salaryHidden;
    self.showEarningsLabel = showEarningsLabel;
    self.hideEarningsLabel = hideEarningsLabel;
    if (running) {
        // 字号交由 -layout 按可用宽度决定，这里只负责内容。
        self.timerLabel.stringValue = time;
        self.detailLabel.stringValue = percent;
        self.salaryLabel.stringValue = salary;
        [self.progressView setProgressValue:progress];
        [self updateSalaryButtonIcon];
    } else {
        self.timerLabel.stringValue = emptyText.length > 0 ? emptyText : @"Countdown not started";
        self.detailLabel.stringValue = @"";
        self.salaryLabel.stringValue = @"";
        [self.progressView setProgressValue:0.0];
    }
    self.needsLayout = YES;
}

- (void)updateSalaryButtonIcon {
    if (!self.hasSalary) {
        self.salaryToggleButton.hidden = YES;
        return;
    }
    self.salaryToggleButton.hidden = NO;
    // 图标表示「点下去会发生什么」，与主窗口 PeriodSummary 的约定一致：
    // 当前已隐藏时显示睁眼（点了会显示），当前可见时显示闭眼（点了会隐藏）。
    NSString *symbol = self.salaryHidden ? @"eye.fill" : @"eye.slash.fill";
    NSString *label = self.salaryHidden ? self.showEarningsLabel : self.hideEarningsLabel;
    if (label.length == 0) label = self.salaryHidden ? @"Show salary" : @"Hide salary";
    self.salaryToggleButton.image = [NSImage imageWithSystemSymbolName:symbol
                                             accessibilityDescription:label];
    self.salaryToggleButton.contentTintColor = [NSColor secondaryLabelColor];
}

- (void)toggleSalaryVisibility {
    self.salaryHidden = !self.salaryHidden;
    [self updateSalaryButtonIcon];
    // 右栏宽度与金额标签的可见性都由 -layout 依据 salaryHidden 决定，
    // 不重排的话要等到下一次托盘 tick（最多一秒）才生效，点击手感是滞后的。
    self.needsLayout = YES;
    extern void owc_native_mini_toggle_salary_ffi(void);
    owc_native_mini_toggle_salary_ffi();
}
@end

@interface OWCNativeMiniController : NSObject
@property(nonatomic, strong) OWCMiniPanel *panel;
@property(nonatomic, strong) OWCMiniContentView *miniContent;
@property(nonatomic, strong, nullable) id globalClickMonitor;
@property(nonatomic, strong, nullable) id localClickMonitor;
+ (instancetype)sharedController;
- (void)toggle;
- (void)hidePanel;
- (void)updateTime:(NSString *)time
           percent:(NSString *)percent
            salary:(NSString *)salary
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText
        showSalary:(BOOL)showSalary
      salaryHidden:(BOOL)salaryHidden
 showEarningsLabel:(NSString *)showEarningsLabel
 hideEarningsLabel:(NSString *)hideEarningsLabel;
@end

@implementation OWCNativeMiniController
+ (instancetype)sharedController {
    static OWCNativeMiniController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[OWCNativeMiniController alloc] init];
    });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _miniContent = [[OWCMiniContentView alloc] initWithFrame:NSMakeRect(0, 0, OWCPanelSize.width, OWCPanelSize.height)];
        _panel = [[OWCMiniPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, OWCPanelSize.width, OWCPanelSize.height)
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _panel.title = @"DoneAt";
        _panel.releasedWhenClosed = NO;
        _panel.opaque = NO;
        _panel.backgroundColor = [NSColor clearColor];
        _panel.hasShadow = YES;
        _panel.level = NSStatusWindowLevel;
        _panel.hidesOnDeactivate = NO;
        _panel.floatingPanel = YES;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary |
            NSWindowCollectionBehaviorTransient |
            NSWindowCollectionBehaviorIgnoresCycle;
        _panel.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;

        NSView *materialView;
        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc]
                initWithFrame:NSMakeRect(0, 0, OWCPanelSize.width, OWCPanelSize.height)];
            glass.cornerRadius = 20.0;
            glass.style = NSGlassEffectViewStyleRegular;
            glass.tintColor = [[NSColor systemOrangeColor] colorWithAlphaComponent:0.035];
            glass.contentView = _miniContent;
            materialView = glass;
        } else {
            NSVisualEffectView *vibrancy = [[NSVisualEffectView alloc]
                initWithFrame:NSMakeRect(0, 0, OWCPanelSize.width, OWCPanelSize.height)];
            vibrancy.material = NSVisualEffectMaterialPopover;
            vibrancy.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            vibrancy.state = NSVisualEffectStateActive;
            vibrancy.wantsLayer = YES;
            vibrancy.layer.cornerRadius = 20.0;
            vibrancy.layer.masksToBounds = YES;
            _miniContent.frame = vibrancy.bounds;
            _miniContent.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [vibrancy addSubview:_miniContent];
            materialView = vibrancy;
        }

        materialView.frame = NSMakeRect(0, 0, OWCPanelSize.width, OWCPanelSize.height);
        materialView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _panel.contentView = materialView;
    }
    return self;
}

- (void)toggle {
    self.panel.visible ? [self hidePanel] : [self showPanel];
}

- (void)updateTime:(NSString *)time
           percent:(NSString *)percent
            salary:(NSString *)salary
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText
        showSalary:(BOOL)showSalary
      salaryHidden:(BOOL)salaryHidden
 showEarningsLabel:(NSString *)showEarningsLabel
 hideEarningsLabel:(NSString *)hideEarningsLabel {
    [self.miniContent updateTime:time
                         percent:percent
                          salary:salary
                        progress:progress
                         running:running
                       emptyText:emptyText
                      showSalary:showSalary
                    salaryHidden:salaryHidden
               showEarningsLabel:showEarningsLabel
               hideEarningsLabel:hideEarningsLabel];
}

- (void)showPanel {
    [self positionBelowMenuBar];
    self.panel.alphaValue = 0.0;
    [self.panel orderFrontRegardless];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.14;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.panel.animator.alphaValue = 1.0;
    } completionHandler:nil];

    __weak OWCNativeMiniController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf installClickMonitors];
    });
}

- (void)hidePanel {
    [self removeClickMonitors];
    [self.panel orderOut:nil];
    self.panel.alphaValue = 1.0;
}

- (void)positionBelowMenuBar {
    NSPoint mouse = [NSEvent mouseLocation];
    NSScreen *targetScreen = nil;
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSMouseInRect(mouse, screen.frame, NO)) {
            targetScreen = screen;
            break;
        }
    }
    targetScreen = targetScreen ?: [NSScreen mainScreen];
    if (!targetScreen) return;

    NSRect visible = targetScreen.visibleFrame;
    CGFloat x = MIN(
        MAX(mouse.x - OWCPanelSize.width / 2.0, NSMinX(visible) + 8.0),
        NSMaxX(visible) - OWCPanelSize.width - 8.0
    );
    CGFloat y = NSMaxY(visible) - OWCPanelSize.height - 7.0;
    [self.panel setFrameOrigin:NSMakePoint(x, y)];
}

- (void)installClickMonitors {
    if (self.globalClickMonitor || self.localClickMonitor || !self.panel.visible) return;

    __weak OWCNativeMiniController *weakSelf = self;
    self.globalClickMonitor = [NSEvent
        addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
        handler:^(__unused NSEvent *event) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf hidePanel];
            });
        }];
    self.localClickMonitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
        handler:^NSEvent *(NSEvent *event) {
            if (event.window != weakSelf.panel) {
                [weakSelf hidePanel];
            }
            return event;
        }];
}

- (void)removeClickMonitors {
    if (self.globalClickMonitor) {
        [NSEvent removeMonitor:self.globalClickMonitor];
        self.globalClickMonitor = nil;
    }
    if (self.localClickMonitor) {
        [NSEvent removeMonitor:self.localClickMonitor];
        self.localClickMonitor = nil;
    }
}
@end

static NSString *OWCStringFromUTF8(const char *value) {
    if (!value) return @"";
    NSString *string = [NSString stringWithUTF8String:value];
    return string ?: @"";
}

void owc_native_mini_initialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        (void)[OWCNativeMiniController sharedController];
    });
}

void owc_native_mini_toggle(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OWCNativeMiniController sharedController] toggle];
    });
}

void owc_native_mini_hide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OWCNativeMiniController sharedController] hidePanel];
    });
}

// Mac App Store builds cannot use WKWebView's private `drawsBackground` KVC
// key. Keep the opaque WebView, but place it edge-to-edge inside a transparent,
// rounded NSWindow using public AppKit/CALayer APIs. The layer mask removes the
// rectangular white corners and the native window supplies the outer shadow.
void owc_configure_store_floating_window(void *windowPointer) {
    if (!windowPointer) return;
    NSWindow *window = (__bridge NSWindow *)windowPointer;
    dispatch_async(dispatch_get_main_queue(), ^{
        window.opaque = NO;
        window.backgroundColor = [NSColor clearColor];
        window.hasShadow = YES;
        NSView *contentView = window.contentView;
        contentView.wantsLayer = YES;
        contentView.layer.cornerRadius = 16.0;
        contentView.layer.masksToBounds = YES;
    });
}

// Store builds use the public macOS 13 login-item API. Status values mirror
// SMAppServiceStatus so Rust can preserve "requires approval" as a locked UI
// state rather than pretending the switch succeeded.
int32_t owc_get_login_item_status(void) {
    if (@available(macOS 13.0, *)) {
        return (int32_t)SMAppService.mainAppService.status;
    }
    return -1;
}

int32_t owc_set_login_item_enabled(int32_t enabled) {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = SMAppService.mainAppService;
        NSError *error = nil;
        BOOL succeeded = enabled
            ? [service registerAndReturnError:&error]
            : [service unregisterAndReturnError:&error];
        if (!succeeded) {
            NSLog(@"Failed to update the main app login item: %@", error);
            return -2;
        }
        return (int32_t)service.status;
    }
    return -1;
}

// Tauri's default AppData resolver points at the user's global
// ~/Library/Application Support directory. A sandboxed Mac App Store build
// must instead ask Foundation for the container-scoped Application Support
// URL, otherwise macOS presents an "other App data" privacy prompt.
int32_t owc_copy_sandbox_store_path(char *buffer, size_t capacity) {
    if (!buffer || capacity == 0) return 0;

    @autoreleasepool {
        NSArray<NSURL *> *urls = [[NSFileManager defaultManager]
            URLsForDirectory:NSApplicationSupportDirectory
                   inDomains:NSUserDomainMask];
        NSURL *applicationSupportURL = urls.firstObject;
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        if (!applicationSupportURL || bundleIdentifier.length == 0) return 0;

        NSURL *storeDirectory = [applicationSupportURL
            URLByAppendingPathComponent:bundleIdentifier
                             isDirectory:YES];
        NSError *error = nil;
        if (![[NSFileManager defaultManager]
                createDirectoryAtURL:storeDirectory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error]) {
            NSLog(@"Failed to create sandbox store directory: %@", error);
            return 0;
        }

        NSURL *storeURL = [storeDirectory
            URLByAppendingPathComponent:@"desktop-state.json"
                             isDirectory:NO];
        const char *path = storeURL.path.fileSystemRepresentation;
        if (!path) return 0;
        size_t length = strlen(path) + 1;
        if (length > capacity) return 0;
        memcpy(buffer, path, length);
        return 1;
    }
}

void owc_native_mini_update(
    const char *timeValue,
    const char *percentValue,
    const char *salaryValue,
    double progress,
    int running,
    const char *emptyTextValue,
    int showSalary,
    int salaryHidden,
    const char *showEarningsLabelValue,
    const char *hideEarningsLabelValue
) {
    NSString *time = [OWCStringFromUTF8(timeValue) copy];
    NSString *percent = [OWCStringFromUTF8(percentValue) copy];
    NSString *salary = [OWCStringFromUTF8(salaryValue) copy];
    NSString *emptyText = [OWCStringFromUTF8(emptyTextValue) copy];
    NSString *showEarningsLabel = [OWCStringFromUTF8(showEarningsLabelValue) copy];
    NSString *hideEarningsLabel = [OWCStringFromUTF8(hideEarningsLabelValue) copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OWCNativeMiniController sharedController]
            updateTime:time
                percent:percent
                 salary:salary
               progress:progress
                running:running != 0
              emptyText:emptyText
             showSalary:showSalary != 0
           salaryHidden:salaryHidden != 0
      showEarningsLabel:showEarningsLabel
      hideEarningsLabel:hideEarningsLabel];
    });
}

int32_t owc_write_widget_snapshot(
    const char *appGroupIdentifierValue,
    const char *storageModeValue,
    const uint8_t *bytes,
    size_t length
) {
    if (!storageModeValue || !bytes || length == 0) return 1;

    NSString *storageMode = OWCStringFromUTF8(storageModeValue);
    NSString *appGroupIdentifier = OWCStringFromUTF8(appGroupIdentifierValue);
    NSURL *containerURL = nil;
    if ([storageMode isEqualToString:@"local-support"]) {
        struct passwd *user = getpwuid(getuid());
        if (!user || !user->pw_dir) return 2;
        NSString *homeDirectory = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:user->pw_dir
                                         length:strlen(user->pw_dir)];
        containerURL = [NSURL fileURLWithPath:[homeDirectory
            stringByAppendingPathComponent:@"Library/Application Support"]
                               isDirectory:YES];
        containerURL = [containerURL
            URLByAppendingPathComponent:
                @"com.rainif.offworkcountdown.macappstore.local-widget"
                             isDirectory:YES];
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager]
                createDirectoryAtURL:containerURL
          withIntermediateDirectories:YES
                           attributes:@{NSFilePosixPermissions: @0700}
                                error:&directoryError]) {
            NSLog(@"Failed to create local Widget snapshot directory: %@", directoryError);
            return 3;
        }
    } else {
        if (appGroupIdentifier.length == 0) return 1;
        containerURL = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier];
    }
    if (!containerURL) return 2;

    NSData *data = [NSData dataWithBytes:bytes length:length];
    NSURL *snapshotURL = [containerURL
        URLByAppendingPathComponent:@"widget-snapshot-v1.json"
        isDirectory:NO];
    NSError *error = nil;
    if (![data writeToURL:snapshotURL options:NSDataWritingAtomic error:&error]) {
        return 3;
    }
    return 0;
}

int32_t owc_effective_appearance_is_dark(void) {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName matched = [NSApp.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[
                NSAppearanceNameAqua,
                NSAppearanceNameDarkAqua
            ]];
        return [matched isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
    }
    return 0;
}

static void (*OWCAppearanceCallback)(void);

@interface OWCAppearanceObserver : NSObject
@end

@implementation OWCAppearanceObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)keyPath;
    (void)object;
    (void)change;
    (void)context;
    if (OWCAppearanceCallback) {
        OWCAppearanceCallback();
    }
}
@end

void owc_on_effective_appearance_change(void (*callback)(void)) {
    OWCAppearanceCallback = callback;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(macOS 10.14, *)) {
            static OWCAppearanceObserver *observer;
            observer = [OWCAppearanceObserver new];
            [NSApp addObserver:observer
                    forKeyPath:@"effectiveAppearance"
                       options:NSKeyValueObservingOptionNew
                       context:NULL];
        }
    });
}
