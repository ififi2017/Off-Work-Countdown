// Lets the app's WKWebViews render JavaScript-driven animation at the display's
// full refresh rate.
//
// WebKit enables "PreferPageRenderingUpdatesNear60FPSEnabled" by default, which
// paces requestAnimationFrame at ~60fps even on a 120Hz ProMotion display.
// Composited CSS animations are unaffected, but the countdown's rolling digits,
// framer-motion transitions and the celebration confetti all run on
// requestAnimationFrame. Measured on an M1 Pro (120Hz): 59fps by default,
// 125fps with the feature off, and switching it on an already loaded view
// takes effect immediately.
//
// The feature switch is WebKit SPI. build.rs compiles this file only with the
// `macos-private-api` feature, so Mac App Store builds (built with
// --no-default-features) never contain these selector names. Every step is
// checked with respondsToSelector:, so a WebKit that drops the SPI simply keeps
// its default pacing.
#import <WebKit/WebKit.h>
#import <objc/message.h>

void owc_allow_full_frame_rate(void *webview) {
    if (webview == NULL) return;
    WKWebView *view = (__bridge WKWebView *)webview;
    if (![view isKindOfClass:[WKWebView class]]) return;

    SEL featuresSelector = NSSelectorFromString(@"_features");
    SEL setSelector = NSSelectorFromString(@"_setEnabled:forFeature:");
    if (![WKPreferences respondsToSelector:featuresSelector]) return;
    // WKWebView.configuration is a copy, but it shares the live WKPreferences.
    WKPreferences *preferences = view.configuration.preferences;
    if (![preferences respondsToSelector:setSelector]) return;

    NSArray *features = ((NSArray * (*)(id, SEL))objc_msgSend)([WKPreferences class], featuresSelector);
    for (id feature in features) {
        if (![feature respondsToSelector:NSSelectorFromString(@"key")]) continue;
        if ([[feature valueForKey:@"key"] isEqual:@"PreferPageRenderingUpdatesNear60FPSEnabled"]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(preferences, setSelector, NO, feature);
            return;
        }
    }
}
