import WidgetKit

private let offWorkCountdownWidgetKind = "com.rainif.offworkcountdown.macappstore.widget"

/// C ABI entry point used by the sandboxed Rust host after an atomic snapshot
/// write. WidgetKit decides when to execute the refreshed timeline.
@_cdecl("owc_reload_widget_timelines")
public func reloadOffWorkCountdownWidgetTimelines() {
    WidgetCenter.shared.reloadTimelines(ofKind: offWorkCountdownWidgetKind)
}
