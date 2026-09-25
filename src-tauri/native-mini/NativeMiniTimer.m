#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
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

/// 与 Web / iOS 同一套倒计时换字参数（RollingText.tsx、OWCMotion.countdownTick）：
/// 线性 0.16s；新字从上方 0.3em 落下，旧字向下 0.3em 淡出，带 3pt 模糊。
static const CFTimeInterval OWCCountdownTickDuration = 0.16;
static const CGFloat OWCCountdownTickOffsetEm = 0.3;
static const CGFloat OWCCountdownTickBlur = 3.0;

/// NSTextField 标签的文字左右各缩进 2pt，照抄，替换前后位置不差一点。
static const CGFloat OWCLabelTextInset = 2.0;

static BOOL OWCIsClockString(NSString *text) {
    if (text.length == 0) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789:"];
    return [text rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

/// 标签里的一段文字：时间里的一个字符，或整句空闲文案。
/// 用 AppKit 直接绘制并允许 vibrancy，和 NSTextField 标签在玻璃 / 毛玻璃上的观感一致。
@interface OWCGlyphView : NSView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSFont *font;
@property(nonatomic, strong) NSColor *textColor;
@end

@implementation OWCGlyphView
- (BOOL)isFlipped { return YES; }
- (BOOL)allowsVibrancy { return YES; }
- (BOOL)isAccessibilityElement { return NO; }

- (void)drawRect:(NSRect)dirtyRect {
    if (self.text.length == 0 || self.font == nil) return;
    [self.text drawAtPoint:NSZeroPoint
            withAttributes:@{
                NSFontAttributeName: self.font,
                NSForegroundColorAttributeName: self.textColor ?: [NSColor labelColor],
            }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

/// 迷你计时的时间标签。接口沿用 NSTextField 的 stringValue / font / textColor /
/// alignment，布局与自适应字号的代码不用改。
///
/// 只有纯数字加冒号的时间串（「2:37:50」）才按字符拆开，每秒只让变了的那一位滚动；
/// 空闲文案有 19 种语言（阿拉伯文、天城文要字形连写），整句绘制、直接换字。
/// 长度或字号变化、面板收起、系统开启「减少动态效果」时也直接换字。
@interface OWCRollingLabel : NSView
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, strong) NSFont *font;
@property(nonatomic, strong) NSColor *textColor;
@property(nonatomic) NSTextAlignment alignment;
- (instancetype)initWithString:(NSString *)text;
@end

@implementation OWCRollingLabel {
    NSMutableArray<OWCGlyphView *> *_glyphs;
    NSMutableArray<OWCGlyphView *> *_outgoing;
}

- (instancetype)initWithString:(NSString *)text {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        _glyphs = [NSMutableArray array];
        _outgoing = [NSMutableArray array];
        _stringValue = [text copy] ?: @"";
        _font = [NSFont systemFontOfSize:NSFont.systemFontSize];
        _textColor = [NSColor labelColor];
        _alignment = NSTextAlignmentLeft;
        [self rebuildGlyphs];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (id)accessibilityValue { return self.stringValue; }

- (void)setStringValue:(NSString *)stringValue {
    NSString *next = [stringValue copy] ?: @"";
    if ([next isEqualToString:_stringValue]) return;
    NSString *previous = _stringValue;
    _stringValue = next;
    if ([self shouldRollFrom:previous to:next]) {
        [self rollFrom:previous to:next];
    } else {
        [self rebuildGlyphs];
    }
}

- (void)setFont:(NSFont *)font {
    // -layout 每次都会重新赋字号；只有真的换了字号才重建，否则会打断正在滚动的数字。
    if (font == nil || [font isEqual:_font]) return;
    _font = font;
    [self rebuildGlyphs];
}

- (void)setTextColor:(NSColor *)textColor {
    _textColor = textColor ?: [NSColor labelColor];
    for (OWCGlyphView *glyph in _glyphs) {
        glyph.textColor = _textColor;
        glyph.needsDisplay = YES;
    }
}

- (void)setAlignment:(NSTextAlignment)alignment {
    if (alignment == _alignment) return;
    _alignment = alignment;
    self.needsLayout = YES;
}

- (BOOL)shouldRollFrom:(NSString *)previous to:(NSString *)next {
    if (!OWCIsClockString(previous) || !OWCIsClockString(next)) return NO;
    if (previous.length != next.length || _glyphs.count != next.length) return NO;
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return NO;
    // 面板收起时是 orderOut，isVisible 就够了。不看 occlusionState：实测菜单栏面板
    // 明明在屏幕上也会报「被遮挡」，加上它数字就永远不滚。
    return self.window.isVisible;
}

- (NSArray<NSString *> *)segmentsForString:(NSString *)text {
    if (!OWCIsClockString(text)) return text.length > 0 ? @[text] : @[];
    NSMutableArray<NSString *> *segments = [NSMutableArray arrayWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        [segments addObject:[text substringWithRange:NSMakeRange(i, 1)]];
    }
    return segments;
}

- (OWCGlyphView *)makeGlyph:(NSString *)text {
    OWCGlyphView *glyph = [[OWCGlyphView alloc] initWithFrame:NSZeroRect];
    glyph.wantsLayer = YES;
    // 换字时要用 CI 模糊。这个开关必须在建视图时就打开：动画开始时才设，AppKit 会
    // 换掉底层图层，已经加上的动画随旧图层一起丢掉。
    glyph.layerUsesCoreImageFilters = YES;
    glyph.text = text;
    glyph.font = self.font;
    glyph.textColor = self.textColor;
    [self addSubview:glyph];
    return glyph;
}

- (void)rebuildGlyphs {
    for (OWCGlyphView *glyph in _outgoing) [glyph removeFromSuperview];
    [_outgoing removeAllObjects];
    for (OWCGlyphView *glyph in _glyphs) [glyph removeFromSuperview];
    [_glyphs removeAllObjects];
    for (NSString *segment in [self segmentsForString:self.stringValue]) {
        [_glyphs addObject:[self makeGlyph:segment]];
    }
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    NSDictionary *attributes = @{NSFontAttributeName: self.font};
    NSMutableArray<NSNumber *> *widths = [NSMutableArray arrayWithCapacity:_glyphs.count];
    CGFloat total = 0.0;
    for (OWCGlyphView *glyph in _glyphs) {
        CGFloat width = [glyph.text sizeWithAttributes:attributes].width;
        [widths addObject:@(width)];
        total += width;
    }

    const CGFloat boundsWidth = self.bounds.size.width;
    CGFloat x = OWCLabelTextInset;
    if (self.alignment == NSTextAlignmentCenter) {
        x = (boundsWidth - total) / 2.0;
    } else if (self.alignment == NSTextAlignmentRight) {
        x = boundsWidth - OWCLabelTextInset - total;
    }

    for (NSUInteger i = 0; i < _glyphs.count; i++) {
        CGFloat width = widths[i].doubleValue;
        // 多留 1pt，避免字形的抗锯齿边缘被视图边界切掉。
        _glyphs[i].frame = NSMakeRect(x, 0.0, ceil(width) + 1.0, self.bounds.size.height);
        x += width;
    }
}

- (void)rollFrom:(NSString *)previous to:(NSString *)next {
    const CGFloat offset = self.font.pointSize * OWCCountdownTickOffsetEm;
    NSMutableArray<OWCGlyphView *> *leaving = [NSMutableArray array];

    [CATransaction begin];
    __weak OWCRollingLabel *weakSelf = self;
    [CATransaction setCompletionBlock:^{
        OWCRollingLabel *label = weakSelf;
        for (OWCGlyphView *glyph in leaving) {
            [glyph removeFromSuperview];
            if (label) [label->_outgoing removeObjectIdenticalTo:glyph];
        }
    }];

    for (NSUInteger i = 0; i < next.length; i++) {
        if ([previous characterAtIndex:i] == [next characterAtIndex:i]) continue;
        OWCGlyphView *old = _glyphs[i];
        OWCGlyphView *incoming = [self makeGlyph:[next substringWithRange:NSMakeRange(i, 1)]];
        incoming.frame = old.frame;
        _glyphs[i] = incoming;
        [_outgoing addObject:old];
        [leaving addObject:old];

        // 本视图 isFlipped，AppKit 让它的图层 geometryFlipped：位移 y 为正就是屏幕上向下。
        // 新字从上方（-offset）落到原位，旧字向下（+offset）离开。
        [self animateGlyph:incoming fromY:-offset toY:0.0 fromOpacity:0.0 toOpacity:1.0
                  fromBlur:OWCCountdownTickBlur toBlur:0.0];
        [self animateGlyph:old fromY:0.0 toY:offset fromOpacity:1.0 toOpacity:0.0
                  fromBlur:0.0 toBlur:OWCCountdownTickBlur];
    }
    [CATransaction commit];
}

- (void)animateGlyph:(OWCGlyphView *)glyph
               fromY:(CGFloat)fromY
                 toY:(CGFloat)toY
         fromOpacity:(float)fromOpacity
           toOpacity:(float)toOpacity
            fromBlur:(CGFloat)fromBlur
              toBlur:(CGFloat)toBlur {
    CALayer *layer = glyph.layer;
    if (layer == nil) return;

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    blur.name = @"blur";
    [blur setValue:@(toBlur) forKey:kCIInputRadiusKey];
    layer.filters = @[blur];
    layer.transform = CATransform3DMakeTranslation(0.0, toY, 0.0);
    layer.opacity = toOpacity;

    CAMediaTimingFunction *linear =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    NSArray<CABasicAnimation *> *animations = @[
        [CABasicAnimation animationWithKeyPath:@"transform.translation.y"],
        [CABasicAnimation animationWithKeyPath:@"opacity"],
        [CABasicAnimation animationWithKeyPath:@"filters.blur.inputRadius"],
    ];
    animations[0].fromValue = @(fromY);
    animations[0].toValue = @(toY);
    animations[1].fromValue = @(fromOpacity);
    animations[1].toValue = @(toOpacity);
    animations[2].fromValue = @(fromBlur);
    animations[2].toValue = @(toBlur);
    for (CABasicAnimation *animation in animations) {
        animation.duration = OWCCountdownTickDuration;
        animation.timingFunction = linear;
        [layer addAnimation:animation forKey:[@"owc.roll." stringByAppendingString:animation.keyPath]];
    }
}
@end

@interface OWCMiniContentView : NSView
@property(nonatomic, strong) OWCRollingLabel *timerLabel;
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
        _timerLabel = [[OWCRollingLabel alloc] initWithString:@"--:--:--"];
        _timerLabel.font = [NSFont monospacedDigitSystemFontOfSize:27.0 weight:NSFontWeightSemibold];
        _timerLabel.textColor = [NSColor labelColor];

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
