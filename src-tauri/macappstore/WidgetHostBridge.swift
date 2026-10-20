import WidgetKit

/// C ABI entry point used by the sandboxed Rust host after an atomic snapshot
/// write. WidgetKit decides when to execute the refreshed timeline.
///
/// Every kind in the extension reads the same snapshot, so every kind has to
/// be reloaded. Reloading only the classic kind left the big digits, ring,
/// timeline and "coming up" styles on whatever timeline they last built
/// (their macOS policy is `.never`) — for example still "off work" after
/// the app had moved on to the next shift.
@_cdecl("owc_reload_widget_timelines")
public func reloadOffWorkCountdownWidgetTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
}
