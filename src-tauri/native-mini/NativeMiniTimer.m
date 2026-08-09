#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

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
@property(nonatomic, strong) OWCNativeProgressView *progressView;
@property(nonatomic) BOOL countdownRunning;
- (void)updateTime:(NSString *)time
            detail:(NSString *)detail
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText;
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

        _detailLabel = [NSTextField labelWithString:@""];
        _detailLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.alignment = NSTextAlignmentRight;
        _detailLabel.lineBreakMode = NSLineBreakByClipping;

        _progressView = [[OWCNativeProgressView alloc] initWithFrame:NSZeroRect];
        [self addSubview:_timerLabel];
        [self addSubview:_detailLabel];
        [self addSubview:_progressView];
    }
    return self;
}

- (void)layout {
    [super layout];
    const CGFloat inset = 16.0;
    self.progressView.frame = NSMakeRect(
        inset,
        11.0,
        self.bounds.size.width - inset * 2.0,
        4.0
    );

    if (self.countdownRunning) {
        self.detailLabel.hidden = NO;
        self.detailLabel.frame = NSMakeRect(
            self.bounds.size.width - inset - 47.0,
            29.0,
            47.0,
            17.0
        );
        self.timerLabel.alignment = NSTextAlignmentLeft;
        self.timerLabel.frame = NSMakeRect(
            inset,
            23.0,
            self.bounds.size.width - inset * 2.0 - 53.0,
            34.0
        );
    } else {
        self.detailLabel.hidden = YES;
        self.timerLabel.alignment = NSTextAlignmentCenter;
        self.timerLabel.frame = NSMakeRect(
            inset,
            23.0,
            self.bounds.size.width - inset * 2.0,
            26.0
        );
    }
}

- (void)updateTime:(NSString *)time
            detail:(NSString *)detail
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText {
    self.countdownRunning = running;
    if (running) {
        self.timerLabel.font = [NSFont monospacedDigitSystemFontOfSize:27.0 weight:NSFontWeightSemibold];
        self.timerLabel.stringValue = time;
        self.detailLabel.stringValue = detail;
        [self.progressView setProgressValue:progress];
    } else {
        self.timerLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
        self.timerLabel.stringValue = emptyText.length > 0 ? emptyText : @"Countdown not started";
        self.detailLabel.stringValue = @"";
        [self.progressView setProgressValue:0.0];
    }
    self.needsLayout = YES;
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
            detail:(NSString *)detail
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText;
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
        _panel.title = @"Off Work Countdown";
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
            detail:(NSString *)detail
          progress:(double)progress
           running:(BOOL)running
         emptyText:(NSString *)emptyText {
    [self.miniContent updateTime:time detail:detail progress:progress running:running emptyText:emptyText];
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

void owc_native_mini_update(
    const char *timeValue,
    const char *detailValue,
    double progress,
    int running,
    const char *emptyTextValue
) {
    NSString *time = [OWCStringFromUTF8(timeValue) copy];
    NSString *detail = [OWCStringFromUTF8(detailValue) copy];
    NSString *emptyText = [OWCStringFromUTF8(emptyTextValue) copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OWCNativeMiniController sharedController]
            updateTime:time
                 detail:detail
               progress:progress
                running:running != 0
              emptyText:emptyText];
    });
}
