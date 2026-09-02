use serde::{Deserialize, Serialize};
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::sync::OnceLock;
use std::{thread, time::Duration};
#[cfg(target_os = "macos")]
use tauri::menu::{AboutMetadata, PredefinedMenuItem, Submenu};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
use tauri::{PhysicalPosition, WebviewUrl, WebviewWindowBuilder};
#[cfg(desktop)]
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};
#[cfg(desktop)]
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_opener::OpenerExt;
#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
use tauri_plugin_positioner::{Position, WindowExt};
use tauri_plugin_store::StoreExt;

#[cfg(not(all(target_os = "macos", not(feature = "self-update"))))]
const STORE_PATH: &str = "desktop-state.json";
const COUNTDOWN_KEY: &str = "countdown";
const NOTIFICATION_MARKER_KEY: &str = "notificationMarker";
#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
const MINI_POSITION_KEY: &str = "miniPosition";
const MINI_ALWAYS_ON_TOP_KEY: &str = "miniAlwaysOnTop";
const GLOBAL_SHORTCUT_SETTINGS_KEY: &str = "globalShortcutSettings";
const DEFAULT_GLOBAL_SHORTCUT: &str = "CommandOrControl+Shift+O";
const DESKTOP_BRAND_NAME: &str = "DoneAt";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct GlobalShortcutSettings {
    enabled: bool,
    accelerator: String,
}

#[cfg(all(test, target_os = "macos", not(feature = "run-key-autostart")))]
mod login_item_tests {
    use super::macos_login_item_state;

    #[test]
    fn a_never_registered_app_is_not_an_error() {
        // 实测：全新 bundle 首次读取 SMAppService.status 得到的是 3（NotFound）
        // 而不是 0（NotRegistered）；register 后变 1，unregister 后才变 0。
        // 把 3 当错误会让每次全新安装后设置页都挂着「桌面设置更新失败」。
        for status in [0, 3] {
            let state = macos_login_item_state(status).expect("should not be an error");
            assert!(!state.enabled);
            assert!(!state.locked);
        }
    }

    #[test]
    fn requires_approval_locks_the_toggle_instead_of_lying() {
        // 用户在系统设置里关掉后，应用请求打开不会报错也不会生效——必须显示成
        // 「被系统接管」，不能显示成已开启。
        let state = macos_login_item_state(2).expect("should not be an error");
        assert!(!state.enabled);
        assert!(state.locked);
    }

    #[test]
    fn distinguishes_unsupported_from_refused() {
        // 两者混为一谈时，注册被拒会被报成「系统版本不支持」，排查方向完全错。
        assert!(macos_login_item_state(-1).unwrap_err().contains("macOS 13"));
        assert!(macos_login_item_state(-2)
            .unwrap_err()
            .contains("System Settings"));
    }
}

#[cfg(all(test, target_os = "macos", not(feature = "self-update")))]
mod widget_snapshot_tests {
    use super::widget_snapshot_contains_sensitive_data;

    #[test]
    fn rejects_sensitive_earnings_fields_at_any_depth() {
        let safe = serde_json::json!({
            "schemaVersion": 1,
            "entries": [{ "remainingEffectiveMsAtDateMs": 1_000 }]
        });
        let unsafe_snapshot = serde_json::json!({
            "schemaVersion": 1,
            "entries": [{ "DailySalary": 100 }]
        });

        assert!(!widget_snapshot_contains_sensitive_data(&safe));
        assert!(widget_snapshot_contains_sensitive_data(&unsafe_snapshot));
    }
}

impl Default for GlobalShortcutSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            accelerator: DEFAULT_GLOBAL_SHORTCUT.into(),
        }
    }
}

/// ObjC 原生面板回调时需要通过 AppHandle 访问 Store。
/// 写入点（setup）与读取点（FFI 回调）都只存在于 macOS。
#[cfg(target_os = "macos")]
static APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();

/// 本地验收开关：让 macOS 的 debug 构建把自己当成 Windows，用来验收
/// Windows 独占的迷你窗（点击唤起主窗口、置顶、关闭按钮等）。
///
/// `debug_assertions` 在 `--release` 下为 false，发版脚本产出的包里整个分支
/// 会被编译器消除，因此这个开关不会出现在正式产物中。
fn windows_mini_dev_override() -> bool {
    cfg!(debug_assertions) && std::env::var_os("OWC_FORCE_WINDOWS_MINI").is_some()
}

/// 3.1 起 macOS 同时保留原生菜单栏面板与可选 WebView 悬浮窗。
#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
fn mini_window_enabled() -> bool {
    cfg!(target_os = "windows") || cfg!(target_os = "macos") || windows_mini_dev_override()
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct ShiftSegment {
    start_at_ms: i64,
    end_at_ms: i64,
}

/// 一条由前端算好的提醒。
///
/// 3.1.6 之前，里程碑跨越、午休边界与健康提醒这三套判定都写在下面的每秒轮询
/// 里——那等于把班次派生规则复制进了 Rust。现在触发时刻与文案都由
/// `lib/reminders.ts` 一次算好，Rust 只比较这些绝对时间戳，回到 AGENTS.md
/// 说的「只能比较和求和前端准备好的绝对 segments」。
///
/// 字段语义以 `lib/reminders.ts` 为准，那边的单元测试是这里的验收标准。
#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct ShiftReminder {
    /// 跨进程稳定的去重键。
    id: String,
    at_ms: i64,
    /// 有效区间是半开的 `[at_ms, expires_at_ms)`；None 表示永不失效。
    expires_at_ms: Option<i64>,
    /// 上一拍到现在的最大允许间隔；None 表示不检查。用来识别设备休眠。
    max_tick_gap_ms: Option<i64>,
    /// 同组一拍跨过多条时只发最晚的一条，其余仅记为已发。
    collapse_group: Option<String>,
    /// None 或空正文表示这条只推进去重标记、不发通知（对应开关关闭）。
    title: Option<String>,
    body: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct ShiftTimelineState {
    segments: Vec<ShiftSegment>,
    planned_end_at_ms: i64,
    overtime_end_at_ms: Option<i64>,
}

impl ShiftTimelineState {
    fn end_at_ms(&self) -> i64 {
        self.overtime_end_at_ms.unwrap_or(self.planned_end_at_ms)
    }

    fn is_valid(&self) -> bool {
        valid_shift_parts(
            &self.segments,
            self.planned_end_at_ms,
            self.overtime_end_at_ms,
        )
    }
}

fn valid_shift_parts(
    segments: &[ShiftSegment],
    planned_end_at_ms: i64,
    overtime_end_at_ms: Option<i64>,
) -> bool {
    let Some(first) = segments.first() else {
        return false;
    };
    if planned_end_at_ms <= first.start_at_ms
        || overtime_end_at_ms.is_some_and(|end| end <= planned_end_at_ms)
    {
        return false;
    }
    let mut previous_end = i64::MIN;
    for segment in segments {
        if segment.end_at_ms <= segment.start_at_ms || segment.start_at_ms < previous_end {
            return false;
        }
        previous_end = segment.end_at_ms;
    }
    let last = segments.last().expect("segments is known to be non-empty");
    planned_end_at_ms > last.start_at_ms
        && planned_end_at_ms <= last.end_at_ms
        && previous_end == overtime_end_at_ms.unwrap_or(planned_end_at_ms)
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct CountdownState {
    /// 共享偏好快照格式；旧版本缺失时 serde 默认成 0。
    #[serde(rename = "preferencesVersion")]
    _preferences_version: u8,
    segments: Vec<ShiftSegment>,
    planned_end_at_ms: i64,
    overtime_end_at_ms: Option<i64>,
    /// 3.0.x Store 兼容字段：反序列化后立即提升为单 segment，不再写回。
    #[serde(rename = "startAtMs", skip_serializing)]
    legacy_start_at_ms: i64,
    #[serde(rename = "endAtMs", skip_serializing)]
    legacy_end_at_ms: i64,
    running: bool,
    next_shift: Option<ShiftTimelineState>,
    /// 本次班次的全部提醒，由前端投影，按 at_ms 升序。
    reminders: Vec<ShiftReminder>,
    /// 提醒列表的修订号；变了说明换了班次，去重记录随之作废。
    reminders_revision: String,
    show_salary: bool,
    hide_earnings: bool,
    daily_salary: Option<f64>,
    lang: String,
    countdown_not_started: String,
    next_shift_label: String,
    /// 迷你窗皮肤，可从悬浮窗工具条直接切换。
    mini_skin: String,
    /// 迷你窗工具条上的声音开关；与主窗口设置项共享同一份状态。
    woodfish_sound_enabled: bool,
    /// 眼睛按钮的无障碍描述。面板其余文案都随界面语言走，这两个如果留在
    /// ObjC 里硬编码英文，VoiceOver 用户会在一堆中文里听到 "Hide salary"。
    show_earnings_label: String,
    hide_earnings_label: String,
}

impl CountdownState {
    fn migrate_legacy(mut self) -> Self {
        if self.segments.is_empty() && self.legacy_end_at_ms > self.legacy_start_at_ms {
            self.segments.push(ShiftSegment {
                start_at_ms: self.legacy_start_at_ms,
                end_at_ms: self.legacy_end_at_ms,
            });
            self.planned_end_at_ms = self.legacy_end_at_ms;
            self.overtime_end_at_ms = None;
        }
        self
    }

    fn end_at_ms(&self) -> i64 {
        self.overtime_end_at_ms.unwrap_or(self.planned_end_at_ms)
    }

    fn is_valid_shift(&self) -> bool {
        valid_shift_parts(
            &self.segments,
            self.planned_end_at_ms,
            self.overtime_end_at_ms,
        )
    }
}

fn advance_to_next_shift(state: &mut CountdownState, now_ms: i64) -> bool {
    if !state.running || !state.is_valid_shift() || now_ms < state.end_at_ms() {
        return false;
    }
    let Some(next) = state.next_shift.clone() else {
        return false;
    };
    if !next.is_valid() {
        state.next_shift = None;
        return true;
    }
    let next_start = next.segments[0].start_at_ms;
    if now_ms < next_start {
        return false;
    }
    if now_ms >= next.end_at_ms() {
        // 睡眠跨过了整班：丢弃过期快照，绝不补发通知。
        state.next_shift = None;
        state.running = false;
        return true;
    }
    state.segments = next.segments;
    state.planned_end_at_ms = next.planned_end_at_ms;
    state.overtime_end_at_ms = next.overtime_end_at_ms;
    state.next_shift = None;
    true
}

/// 必须与 `lib/reminders.ts` 的 `REMINDER_MODEL_VERSION` 一致。不一致时旧标记
/// 整份作废，而不是拿旧语义去比对新列表。
const REMINDER_MODEL_VERSION: u8 = 1;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct ReminderMarker {
    model_version: u8,
    /// 前端给出的列表修订号。
    revision: String,
    sent_ids: Vec<String>,
    last_observed_ms: i64,
}

#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
struct MiniPosition {
    x: i32,
    y: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MiniWindowSettings {
    platform: &'static str,
    always_on_top: bool,
}

/// 托盘用 show / mini / quit，其余字段只喂给 macOS 的应用菜单。非 macOS 上
/// 它们确实没有读取方，但仍要参与反序列化——前端一次性发全量标签，缺字段会
/// 让整条命令失败。macOS 上所有字段都被读取，那边的 dead_code 检查照常生效。
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DesktopMenuLabels {
    /// 「关于」面板里的应用名。跟着**应用**语言走，与其余菜单项一致。
    ///
    /// ⚠️ 管不到菜单栏最左侧那个粗体应用名。那个标题由 AppKit 从 bundle 名
    /// 派生，给第一个 Submenu 设标题会被忽略（实机验证过）。菜单栏那个名字由
    /// macos-lproj 里的 CFBundleName 决定。品牌名固定为 DoneAt，不随语言翻译。
    app_name: String,
    show: String,
    mini: String,
    quit: String,
    file: String,
    edit: String,
    view: String,
    window: String,
    help: String,
    about: String,
    services: String,
    hide_app: String,
    hide_others: String,
    close_window: String,
    undo: String,
    redo: String,
    cut: String,
    copy: String,
    paste: String,
    select_all: String,
    toggle_full_screen: String,
    minimize: String,
    zoom: String,
    bring_all_to_front: String,
}

impl Default for DesktopMenuLabels {
    fn default() -> Self {
        Self {
            app_name: DESKTOP_BRAND_NAME.into(),
            show: "Show app".into(),
            mini: "Mini timer".into(),
            quit: "Quit".into(),
            file: "File".into(),
            edit: "Edit".into(),
            view: "View".into(),
            window: "Window".into(),
            help: "Help".into(),
            about: "About DoneAt".into(),
            services: "Services".into(),
            hide_app: "Hide DoneAt".into(),
            hide_others: "Hide Others".into(),
            close_window: "Close Window".into(),
            undo: "Undo".into(),
            redo: "Redo".into(),
            cut: "Cut".into(),
            copy: "Copy".into(),
            paste: "Paste".into(),
            select_all: "Select All".into(),
            toggle_full_screen: "Toggle Full Screen".into(),
            minimize: "Minimize".into(),
            zoom: "Zoom".into(),
            bring_all_to_front: "Bring All to Front".into(),
        }
    }
}

#[cfg(target_os = "macos")]
mod native_mini {
    use std::ffi::{c_char, CString};
    // 只有商店渠道会走沙盒容器路径和公开 AppKit 悬浮窗，GitHub 版编译不到这些
    // 符号——连 use 一起 cfg 掉，否则默认 feature 下就是一串 unused 警告，而 CI
    // 的 clippy 带 -D warnings。
    #[cfg(not(feature = "self-update"))]
    use std::ffi::{c_void, CStr};
    #[cfg(not(feature = "self-update"))]
    use std::path::PathBuf;

    extern "C" {
        fn owc_native_mini_initialize();
        fn owc_native_mini_toggle();
        fn owc_native_mini_hide();
        #[cfg(not(feature = "self-update"))]
        fn owc_configure_store_floating_window(window: *mut c_void);
        #[cfg(not(feature = "self-update"))]
        fn owc_copy_sandbox_store_path(buffer: *mut c_char, capacity: usize) -> i32;
        #[cfg(not(feature = "run-key-autostart"))]
        fn owc_get_login_item_status() -> i32;
        #[cfg(not(feature = "run-key-autostart"))]
        fn owc_set_login_item_enabled(enabled: i32) -> i32;
        fn owc_native_mini_update(
            time: *const c_char,
            percent: *const c_char,
            salary: *const c_char,
            progress: f64,
            running: i32,
            empty_text: *const c_char,
            show_salary: i32,
            salary_hidden: i32,
            show_earnings_label: *const c_char,
            hide_earnings_label: *const c_char,
        );
        fn owc_effective_appearance_is_dark() -> i32;
        fn owc_on_effective_appearance_change(callback: Option<extern "C" fn()>);
    }

    fn c_string(value: &str) -> CString {
        CString::new(value.replace('\0', "")).expect("sanitized native Mini Timer text")
    }

    pub fn initialize() {
        unsafe { owc_native_mini_initialize() }
    }

    pub fn toggle() {
        unsafe { owc_native_mini_toggle() }
    }

    #[allow(dead_code)]
    pub fn hide() {
        unsafe { owc_native_mini_hide() }
    }

    #[cfg(not(feature = "self-update"))]
    pub fn configure_store_floating_window(window: *mut c_void) {
        unsafe { owc_configure_store_floating_window(window) }
    }

    #[cfg(not(feature = "self-update"))]
    pub fn sandbox_store_path() -> Option<PathBuf> {
        let mut buffer = [0 as c_char; 4096];
        let copied = unsafe { owc_copy_sandbox_store_path(buffer.as_mut_ptr(), buffer.len()) };
        if copied == 0 {
            return None;
        }
        let path = unsafe { CStr::from_ptr(buffer.as_ptr()) }
            .to_string_lossy()
            .into_owned();
        Some(PathBuf::from(path))
    }

    #[cfg(not(feature = "run-key-autostart"))]
    pub fn login_item_status() -> i32 {
        unsafe { owc_get_login_item_status() }
    }

    #[cfg(not(feature = "run-key-autostart"))]
    pub fn set_login_item_enabled(enabled: bool) -> i32 {
        unsafe { owc_set_login_item_enabled(i32::from(enabled)) }
    }

    // 参数表就是对面 C 函数的签名本身，为了少几个参数去包一层结构体，
    // 只会在 FFI 边界上多一次拆包，读起来反而更绕。
    #[allow(clippy::too_many_arguments)]
    pub fn update(
        time: &str,
        percent: &str,
        salary: &str,
        progress: f64,
        running: bool,
        empty_text: &str,
        show_salary: bool,
        salary_hidden: bool,
        show_earnings_label: &str,
        hide_earnings_label: &str,
    ) {
        let time = c_string(time);
        let percent = c_string(percent);
        let salary = c_string(salary);
        let empty_text = c_string(empty_text);
        let show_earnings_label = c_string(show_earnings_label);
        let hide_earnings_label = c_string(hide_earnings_label);
        unsafe {
            owc_native_mini_update(
                time.as_ptr(),
                percent.as_ptr(),
                salary.as_ptr(),
                progress,
                i32::from(running),
                empty_text.as_ptr(),
                i32::from(show_salary),
                i32::from(salary_hidden),
                show_earnings_label.as_ptr(),
                hide_earnings_label.as_ptr(),
            )
        }
    }

    pub fn effective_appearance_is_dark() -> bool {
        unsafe { owc_effective_appearance_is_dark() != 0 }
    }

    pub fn on_effective_appearance_change(callback: extern "C" fn()) {
        unsafe { owc_on_effective_appearance_change(Some(callback)) }
    }
}

#[cfg(all(target_os = "macos", not(feature = "self-update")))]
static SANDBOX_STORE_PATH: OnceLock<Result<PathBuf, String>> = OnceLock::new();

fn desktop_store_path() -> Result<PathBuf, String> {
    // 两个分支互斥，各自都是函数的尾表达式，因此不能写 `return`——另一个分支在
    // 编译时整块消失，`return` 就成了 clippy::needless_return。这条只在对应渠道
    // 上跑 clippy 才会暴露。
    #[cfg(all(target_os = "macos", not(feature = "self-update")))]
    {
        SANDBOX_STORE_PATH
            .get_or_init(|| {
                native_mini::sandbox_store_path().ok_or_else(|| {
                    "macOS sandbox Application Support directory is unavailable".to_string()
                })
            })
            .clone()
    }

    #[cfg(not(all(target_os = "macos", not(feature = "self-update"))))]
    {
        Ok(PathBuf::from(STORE_PATH))
    }
}

fn desktop_store<R: tauri::Runtime>(
    app: &AppHandle<R>,
) -> Result<std::sync::Arc<tauri_plugin_store::Store<R>>, String> {
    let path = desktop_store_path()?;
    app.store(path).map_err(|error| error.to_string())
}

#[cfg(all(target_os = "macos", not(feature = "self-update")))]
#[tauri::command]
fn get_desktop_store_path() -> Result<String, String> {
    desktop_store_path().map(|path| path.to_string_lossy().into_owned())
}

#[cfg(all(target_os = "macos", not(feature = "self-update")))]
mod macos_widget {
    use std::ffi::{c_char, CString};

    extern "C" {
        fn owc_write_widget_snapshot(
            app_group_identifier: *const c_char,
            storage_mode: *const c_char,
            bytes: *const u8,
            length: usize,
        ) -> i32;
        fn owc_reload_widget_timelines();
    }

    pub fn write_snapshot(snapshot_json: &str) -> Result<(), String> {
        const STORAGE_MODE: &str = env!("OWC_WIDGET_STORAGE_MODE");
        // build.rs 在有 Team ID 时会把 iOS 的 group.* 加上前缀，与 entitlements 对齐。
        const APP_GROUP_IDENTIFIER: &str = env!("OWC_APP_GROUP_IDENTIFIER");
        let app_group_identifier = CString::new(APP_GROUP_IDENTIFIER)
            .map_err(|_| "the Widget App Group identifier contains a NUL byte".to_string())?;
        let storage_mode = CString::new(STORAGE_MODE)
            .map_err(|_| "the Widget storage mode contains a NUL byte".to_string())?;
        let result = unsafe {
            owc_write_widget_snapshot(
                app_group_identifier.as_ptr(),
                storage_mode.as_ptr(),
                snapshot_json.as_bytes().as_ptr(),
                snapshot_json.len(),
            )
        };
        match result {
            0 => {
                unsafe { owc_reload_widget_timelines() };
                Ok(())
            }
            1 => Err("the Widget snapshot payload or storage configuration is invalid".into()),
            2 => Err(format!(
                "the App Group container is unavailable: {}",
                app_group_identifier.to_string_lossy()
            )),
            _ => Err("the Widget snapshot could not be written atomically".into()),
        }
    }
}

/// ObjC 原生面板点击眼睛按钮时回调 Rust，翻转 hide_earnings 状态。
#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn owc_native_mini_toggle_salary_ffi() {
    if let Some(app) = APP_HANDLE.get() {
        flip_hide_earnings(app);
    }
}

fn platform_name() -> &'static str {
    // 本地验收时对前端也谎报平台，否则迷你窗里的 Windows 专属交互不会启用。
    if windows_mini_dev_override() {
        return "windows";
    }
    #[cfg(target_os = "macos")]
    return "macos";
    #[cfg(target_os = "windows")]
    return "windows";
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    return "other";
}

/// 显示并聚焦主窗口。窗口可能处于隐藏（关闭到托盘）或最小化状态，
/// 三步都要做，只调 set_focus 对隐藏窗口无效。
fn focus_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// 全局快捷键是切换器：当前正在使用主窗口时隐藏，否则从托盘状态恢复并聚焦。
fn toggle_main_window(app: &AppHandle) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    let visible = window.is_visible().unwrap_or(false);
    let focused = window.is_focused().unwrap_or(false);
    if visible && focused {
        let _ = window.hide();
    } else {
        focus_main_window(app);
    }
}

fn toggle_mini_window(app: &AppHandle) {
    // 本地验收 Windows 迷你窗时不要同时弹出 macOS 原生面板，否则两个都在。
    #[cfg(target_os = "macos")]
    if !windows_mini_dev_override() {
        native_mini::toggle();
        return;
    }

    #[cfg(any(target_os = "windows", debug_assertions))]
    {
        let Some(window) = app.get_webview_window("mini") else {
            return;
        };

        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
            return;
        }

        let _ = window.show();
        let _ = window.set_focus();
    }

    let _ = app;
}

fn toggle_floating_window(app: &AppHandle) {
    #[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
    if let Some(window) = app.get_webview_window("mini") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
    let _ = app;
}

fn hide_mini_window(app: &AppHandle) {
    #[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
    if let Some(window) = app.get_webview_window("mini") {
        let _ = window.hide();
    }

    let _ = app;
}

fn read_countdown_state(app: &AppHandle) -> CountdownState {
    desktop_store(app)
        .ok()
        .and_then(|store| store.get(COUNTDOWN_KEY))
        .and_then(|value| serde_json::from_value::<CountdownState>(value).ok())
        .unwrap_or_default()
        .migrate_legacy()
}

fn write_countdown_state(app: &AppHandle, state: &CountdownState) {
    let Ok(store) = desktop_store(app) else {
        return;
    };
    if let Ok(value) = serde_json::to_value(state) {
        store.set(COUNTDOWN_KEY, value);
        let _ = store.save();
    }
}

fn read_reminder_marker(app: &AppHandle) -> ReminderMarker {
    desktop_store(app)
        .ok()
        .and_then(|store| store.get(NOTIFICATION_MARKER_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn write_reminder_marker(app: &AppHandle, marker: &ReminderMarker) {
    let Ok(store) = desktop_store(app) else {
        return;
    };
    if let Ok(value) = serde_json::to_value(marker) {
        store.set(NOTIFICATION_MARKER_KEY, value);
        let _ = store.save();
    }
}

/// 推进一次提醒状态，返回本拍应当发出的通知。
///
/// 判定规则的唯一实现在 `lib/reminders.ts` 的 `selectDueReminders`；那边的单元
/// 测试就是这个函数的验收标准，两处必须给出同一个结果。这里只做三件事：
/// 按跨越挑出候选、按有效期与跳拍间隔过滤、按分组折叠。
///
/// 返回的 bool 表示标记是否需要落盘。`last_observed_ms` 由调用方在每一拍更新，
/// 但只在这里返回 true 时才写盘——每秒写一次 Store 没有意义，而两次写盘之间
/// 的那个较旧的 `previous` 正是重启后不补发陈旧提醒所需要的。
fn advance_reminders<'a>(
    state: &'a CountdownState,
    marker: &mut ReminderMarker,
    now_ms: i64,
) -> (Vec<&'a ShiftReminder>, bool) {
    if marker.model_version != REMINDER_MODEL_VERSION || marker.revision != state.reminders_revision
    {
        // 第一次看到这份列表：以当前时刻为基线，此前越过的提醒一律不补发。
        *marker = ReminderMarker {
            model_version: REMINDER_MODEL_VERSION,
            revision: state.reminders_revision.clone(),
            sent_ids: Vec::new(),
            last_observed_ms: now_ms,
        };
        return (Vec::new(), true);
    }

    let previous = marker.last_observed_ms;
    if now_ms <= previous {
        // 系统时钟回拨：不发任何通知，调用方随后会把基线拉回来。
        return (Vec::new(), false);
    }

    let crossed: Vec<&ShiftReminder> = state
        .reminders
        .iter()
        .filter(|reminder| reminder.at_ms > previous && reminder.at_ms <= now_ms)
        .filter(|reminder| !marker.sent_ids.iter().any(|id| id == &reminder.id))
        .collect();
    if crossed.is_empty() {
        return (Vec::new(), false);
    }

    let mut audible: Vec<&ShiftReminder> = crossed
        .iter()
        .copied()
        .filter(|reminder| {
            let expired = match reminder.expires_at_ms {
                Some(expires) => now_ms >= expires,
                None => false,
            };
            let stale_tick = match reminder.max_tick_gap_ms {
                Some(gap) => now_ms - previous > gap,
                None => false,
            };
            let has_body = reminder
                .body
                .as_deref()
                .is_some_and(|body| !body.is_empty());
            reminder.title.is_some() && has_body && !expired && !stale_tick
        })
        .collect();
    audible.sort_by_key(|reminder| reminder.at_ms);

    // 折叠：同组只留触发时刻最晚的一条。休眠一次跨过 50%、75%、90% 三档时，
    // 连弹三条只是噪音——用户想知道的是「现在到哪儿了」。
    let mut due: Vec<&'a ShiftReminder> = Vec::new();
    for reminder in audible {
        match reminder.collapse_group.as_deref() {
            None => due.push(reminder),
            Some(group) => {
                let existing = due
                    .iter_mut()
                    .find(|kept| kept.collapse_group.as_deref() == Some(group));
                match existing {
                    // audible 已按 at_ms 升序，后来的天然更晚，直接顶掉先前那条。
                    Some(slot) => *slot = reminder,
                    None => due.push(reminder),
                }
            }
        }
    }
    due.sort_by_key(|reminder| reminder.at_ms);

    // 被折叠掉的、被有效期挡掉的、以及开关关闭的，同样记为已发：
    // 否则下一拍它们会重新算进候选，或者在用户中途打开开关时集体补弹。
    for reminder in crossed {
        marker.sent_ids.push(reminder.id.clone());
    }
    marker.sent_ids.sort();
    marker.sent_ids.dedup();

    (due, true)
}

#[cfg(desktop)]
fn send_reminder(app: &AppHandle, reminder: &ShiftReminder) {
    let (Some(title), Some(body)) = (reminder.title.as_deref(), reminder.body.as_deref()) else {
        return;
    };
    if let Err(error) = app.notification().builder().title(title).body(body).show() {
        log::warn!("failed to send reminder {}: {error}", reminder.id);
    }
}

/// 当前时刻若落在两个 segment 之间的空隙里，返回该空隙的结束时间。
///
/// 与前端 `getActiveBreakEndAtMs` 同口径：这里不认识「午休」这个业务概念，
/// 只判断时间轴上的洞——业务规则仍然只存在于 lib/countdown.ts。
fn active_break_end_at_ms(state: &CountdownState, now_ms: i64) -> Option<i64> {
    state.segments.windows(2).find_map(|pair| {
        let gap_start = pair[0].end_at_ms;
        let gap_end = pair[1].start_at_ms;
        (gap_end > gap_start && now_ms >= gap_start && now_ms < gap_end).then_some(gap_end)
    })
}

/// ⚠️ 向下取整，与 lib/desktop-state.ts 的 formatDesktopDuration 保持一致。
/// 桌面小组件由系统的 `Text(date, style: .timer)` 渲染，取整方式改不了，因此它
/// 是基准；这里原本是 `(x + 999) / 1000`（向上取整），会让托盘和原生面板恒定
/// 比小组件与主窗口多显示一秒。
fn format_remaining(remaining_ms: i64) -> String {
    let total_seconds = remaining_ms.max(0) / 1000;
    let hours = total_seconds / 3600;
    let minutes = (total_seconds % 3600) / 60;
    let seconds = total_seconds % 60;
    format!("{hours}:{minutes:02}:{seconds:02}")
}

/// 非 macOS 构建里只有单元测试会调用它（原生面板是 macOS 独有的）。
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn countdown_progress(state: &CountdownState, now_ms: i64) -> f64 {
    countdown_metrics(state, now_ms)
        .map(|(_, progress)| progress)
        .unwrap_or(0.0)
}

/// 只有 macOS 原生面板会显示金额；Windows 迷你窗自己从 Store 算。
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn countdown_pay_ratio(state: &CountdownState, now_ms: i64) -> f64 {
    if !state.running || !state.is_valid_shift() {
        return 0.0;
    }
    let planned_duration: i64 = state
        .segments
        .iter()
        .map(|segment| {
            (segment.end_at_ms.min(state.planned_end_at_ms) - segment.start_at_ms).max(0)
        })
        .sum();
    if planned_duration <= 0 {
        return 0.0;
    }
    let elapsed: i64 = state
        .segments
        .iter()
        .map(|segment| {
            (now_ms - segment.start_at_ms).clamp(0, segment.end_at_ms - segment.start_at_ms)
        })
        .sum();
    (elapsed as f64 / planned_duration as f64).max(0.0)
}

/// 只对前端给出的绝对 segments 求和，不推导跨夜、工作日、午休或加班规则。
/// 位于两个 segment 之间时 elapsed 不变，因此剩余时间与进度都会暂停。
fn countdown_metrics(state: &CountdownState, now_ms: i64) -> Option<(i64, f64)> {
    if !state.running || !state.is_valid_shift() {
        return None;
    }

    let duration: i64 = state
        .segments
        .iter()
        .map(|segment| segment.end_at_ms - segment.start_at_ms)
        .sum();
    if duration <= 0 {
        return None;
    }
    let elapsed: i64 = state
        .segments
        .iter()
        .map(|segment| {
            (now_ms - segment.start_at_ms).clamp(0, segment.end_at_ms - segment.start_at_ms)
        })
        .sum();
    Some((
        duration - elapsed,
        (elapsed as f64 / duration as f64).clamp(0.0, 1.0),
    ))
}

/// 独立于 WebView 的后台节拍器。这里只比较、累加前端给出的绝对 segments；
/// 跨夜班次等业务规则仍由前端唯一实现。即便主窗口隐藏，托盘与迷你窗生命周期
/// 也不受影响。
fn start_tray_timer(app: AppHandle) {
    thread::spawn(move || {
        #[cfg(any(target_os = "windows", debug_assertions))]
        let mut was_running = false;
        let mut marker = read_reminder_marker(&app);
        loop {
            let now_ms = chrono_free_now_ms();
            let mut state = read_countdown_state(&app);
            if advance_to_next_shift(&mut state, now_ms) {
                write_countdown_state(&app, &state);
            }
            let metrics = countdown_metrics(&state, now_ms);
            let shift_start_at_ms = state
                .segments
                .first()
                .map(|segment| segment.start_at_ms)
                .unwrap_or_default();
            let active =
                metrics.is_some() && shift_start_at_ms <= now_ms && state.end_at_ms() > now_ms;
            let current_start_remaining = (!active && state.running && state.is_valid_shift())
                .then_some(shift_start_at_ms)
                .filter(|start| *start > now_ms)
                .map(|start| format_remaining(start - now_ms));
            #[cfg(any(target_os = "windows", debug_assertions))]
            let waiting_for_current_shift = current_start_remaining.is_some();
            // 午休时托盘显示距午休结束的时间，而不是冻住的下班倒计时——
            // 后者在整个午休期间纹丝不动，看起来像应用卡死了。
            let break_remaining = active
                .then(|| active_break_end_at_ms(&state, now_ms))
                .flatten()
                .map(|end| format_remaining(end - now_ms));
            let remaining = break_remaining
                .clone()
                .or_else(|| active.then(|| format_remaining(metrics.expect("active metrics").0)));
            let next_remaining = current_start_remaining.or_else(|| {
                (!active && state.running)
                    .then_some(state.next_shift.as_ref())
                    .flatten()
                    .filter(|next| next.is_valid() && next.segments[0].start_at_ms > now_ms)
                    .map(|next| format_remaining(next.segments[0].start_at_ms - now_ms))
            });

            let (due_reminders, marker_changed) = advance_reminders(&state, &mut marker, now_ms);
            marker.last_observed_ms = now_ms;
            // 先落盘再发送，与重构前的顺序一致：万一进程在两者之间崩溃，
            // 宁可漏一条，也不要重启后把同一条重新弹一遍。
            if marker_changed {
                write_reminder_marker(&app, &marker);
            }
            for reminder in due_reminders {
                send_reminder(&app, reminder);
            }

            if let Some(tray) = app.tray_by_id("main") {
                #[cfg(target_os = "macos")]
                let _ = tray.set_title(Some(
                    remaining
                        .as_deref()
                        .or(next_remaining.as_deref())
                        .unwrap_or(""),
                ));

                let tooltip = remaining
                    .as_deref()
                    .or(next_remaining.as_deref())
                    .map(|time| format!("{DESKTOP_BRAND_NAME} · {time}"))
                    .unwrap_or_else(|| DESKTOP_BRAND_NAME.to_string());
                let _ = tray.set_tooltip(Some(tooltip));
            }

            #[cfg(target_os = "macos")]
            {
                // 只有原生面板用得到进度值；Windows 迷你窗自己从 store 算，
                // 放在外层会变成每秒算一次然后丢掉。
                let progress = countdown_progress(&state, now_ms);
                // 百分比与金额分成两个字段下发。早期版本把它们拼成
                // "90% 645.37" 再由 ObjC 按空格切开，一旦金额改用带分隔符的
                // 本地化格式（法语千分位就是空格）就会静默错位。
                let percent = format!("{}%", (progress * 100.0).floor() as i64);
                let percent_text = if active { percent.as_str() } else { "" };
                // 开了「显示薪资」但金额栏为空时 daily_salary 是 NaN，此时没有
                // 可显示的金额，眼睛按钮和右侧的金额行都不应该占位。
                let salary_text = if active && state.show_salary {
                    state
                        .daily_salary
                        .filter(|salary| salary.is_finite())
                        .map(|salary| {
                            format!("{:.2}", salary * countdown_pay_ratio(&state, now_ms))
                        })
                        .unwrap_or_default()
                } else {
                    String::new()
                };
                let between_text = next_remaining.as_ref().map(|time| {
                    let template = if state.next_shift_label.is_empty() {
                        "Next shift in __TIME__"
                    } else {
                        &state.next_shift_label
                    };
                    template.replace("__TIME__", time)
                });
                let empty_text = if let Some(text) = between_text.as_deref() {
                    text
                } else if state.countdown_not_started.is_empty() {
                    "Countdown not started"
                } else {
                    &state.countdown_not_started
                };
                native_mini::update(
                    remaining.as_deref().unwrap_or(""),
                    percent_text,
                    &salary_text,
                    progress,
                    active,
                    empty_text,
                    !salary_text.is_empty(),
                    state.hide_earnings,
                    &state.show_earnings_label,
                    &state.hide_earnings_label,
                );
            }

            #[cfg(any(target_os = "windows", debug_assertions))]
            // Windows 在等待本班开始或正式倒计时时自动露出迷你窗；结束后不再强制隐藏，
            // 已经打开的窗口会切换为“计时未开始”，由用户决定是否收起。
            if (cfg!(target_os = "windows") || windows_mini_dev_override())
                && (active || waiting_for_current_shift)
                && !was_running
            {
                if let Some(window) = app.get_webview_window("mini") {
                    let _ = window.show();
                }
            }

            #[cfg(any(target_os = "windows", debug_assertions))]
            {
                was_running = active || waiting_for_current_shift;
            }
            // 对齐到墙上时钟的整秒边界，而不是固定 sleep(1s)：后者每轮实际是
            // 「本轮工作耗时 + 1s」，会累积漂移，与主窗口、迷你窗那两个独立计时器
            // 越走越远，同一时刻三处显示不同的秒数。见 lib/second-tick.ts。
            let into_second = (chrono_free_now_ms() % 1000) as u64;
            thread::sleep(Duration::from_millis(1000 - into_second.min(999)));
        }
    });
}

fn chrono_free_now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

/// 托盘图标与菜单：右键打开菜单，左键直接切换迷你窗。
fn build_tray_menu(app: &AppHandle, labels: &DesktopMenuLabels) -> tauri::Result<Menu<tauri::Wry>> {
    let show = MenuItem::with_id(app, "show", &labels.show, true, None::<&str>)?;
    let mini = MenuItem::with_id(app, "mini", &labels.mini, true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", &labels.quit, true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &mini, &quit])?;
    Ok(menu)
}

/// macOS 菜单栏用透明 UI mark，不要用带紫底的 App 图标。浅色菜单栏走梅紫指针，
/// 深色菜单栏走米色指针；橙环两边通用。不要 `icon_as_template`，否则会变成单色剪影。
///
/// `include_image!` 按 `CARGO_MANIFEST_DIR` 解析路径，编译期展开成 RGBA，
/// 不依赖 `image-png` feature。
#[cfg(target_os = "macos")]
fn macos_tray_icon() -> tauri::image::Image<'static> {
    if native_mini::effective_appearance_is_dark() {
        tauri::include_image!("icons/macos-tray-mark-dark.png")
    } else {
        tauri::include_image!("icons/macos-tray-mark.png")
    }
}

fn tray_icon(app: &AppHandle) -> tauri::image::Image<'_> {
    #[cfg(target_os = "macos")]
    {
        let _ = app;
        macos_tray_icon()
    }
    #[cfg(not(target_os = "macos"))]
    {
        app.default_window_icon()
            .expect("bundle icon missing")
            .clone()
    }
}

#[cfg(target_os = "macos")]
extern "C" fn refresh_macos_tray_icon() {
    let Some(app) = APP_HANDLE.get() else {
        return;
    };
    let Some(tray) = app.tray_by_id("main") else {
        return;
    };
    let _ = tray.set_icon(Some(macos_tray_icon()));
}

fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let menu = build_tray_menu(app, &DesktopMenuLabels::default())?;
    let icon = tray_icon(app);

    let builder = TrayIconBuilder::with_id("main")
        .icon(icon)
        .tooltip(DESKTOP_BRAND_NAME)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => focus_main_window(app),
            "mini" => toggle_mini_window(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
            if matches!(
                event,
                TrayIconEvent::Click {
                    button: MouseButton::Left,
                    button_state: MouseButtonState::Up,
                    ..
                }
            ) {
                toggle_mini_window(tray.app_handle());
            }
        });

    #[cfg(target_os = "macos")]
    let builder = builder.icon_as_template(false);

    builder.build(app)?;

    Ok(())
}

/// 用前端当前语言重建 macOS 菜单栏。PredefinedMenuItem 保留系统快捷键和原生
/// selector，只替换可见文案；应用名按 D2 始终保持英文产品名。
#[cfg(target_os = "macos")]
fn set_macos_application_menu(app: &AppHandle, labels: &DesktopMenuLabels) -> tauri::Result<()> {
    let package = app.package_info();
    let about_metadata = AboutMetadata {
        name: Some(labels.app_name.clone()),
        version: Some(package.version.to_string()),
        copyright: app.config().bundle.copyright.clone(),
        authors: app
            .config()
            .bundle
            .publisher
            .clone()
            .map(|value| vec![value]),
        ..Default::default()
    };

    let app_menu = Submenu::with_items(
        app,
        &labels.app_name,
        true,
        &[
            &PredefinedMenuItem::about(app, Some(&labels.about), Some(about_metadata))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::services(app, Some(&labels.services))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::hide(app, Some(&labels.hide_app))?,
            &PredefinedMenuItem::hide_others(app, Some(&labels.hide_others))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::quit(app, Some(&labels.quit))?,
        ],
    )?;
    let file_menu = Submenu::with_items(
        app,
        &labels.file,
        true,
        &[&PredefinedMenuItem::close_window(
            app,
            Some(&labels.close_window),
        )?],
    )?;
    let edit_menu = Submenu::with_items(
        app,
        &labels.edit,
        true,
        &[
            &PredefinedMenuItem::undo(app, Some(&labels.undo))?,
            &PredefinedMenuItem::redo(app, Some(&labels.redo))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, Some(&labels.cut))?,
            &PredefinedMenuItem::copy(app, Some(&labels.copy))?,
            &PredefinedMenuItem::paste(app, Some(&labels.paste))?,
            &PredefinedMenuItem::select_all(app, Some(&labels.select_all))?,
        ],
    )?;
    let view_menu = Submenu::with_items(
        app,
        &labels.view,
        true,
        &[&PredefinedMenuItem::fullscreen(
            app,
            Some(&labels.toggle_full_screen),
        )?],
    )?;
    let window_menu = Submenu::with_items(
        app,
        &labels.window,
        true,
        &[
            &PredefinedMenuItem::minimize(app, Some(&labels.minimize))?,
            &PredefinedMenuItem::maximize(app, Some(&labels.zoom))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::close_window(app, Some(&labels.close_window))?,
            &PredefinedMenuItem::bring_all_to_front(app, Some(&labels.bring_all_to_front))?,
        ],
    )?;
    let help_menu = Submenu::new(app, &labels.help, true)?;
    let menu = Menu::with_items(
        app,
        &[
            &app_menu,
            &file_menu,
            &edit_menu,
            &view_menu,
            &window_menu,
            &help_menu,
        ],
    )?;
    app.set_menu(menu)?;
    Ok(())
}

#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
fn setup_mini_window(app: &AppHandle) -> tauri::Result<()> {
    let store = desktop_store(app).map_err(|error| std::io::Error::other(error.to_string()))?;
    let always_on_top = store
        .get(MINI_ALWAYS_ON_TOP_KEY)
        .and_then(|value| value.as_bool())
        .unwrap_or(true);
    let force_woodfish = cfg!(debug_assertions) && std::env::var_os("OWC_FORCE_WOODFISH").is_some();
    let url = if cfg!(debug_assertions) && force_woodfish {
        "en/mini?skin=woodfish"
    } else if cfg!(debug_assertions) {
        "en/mini"
    } else {
        "en/mini.html"
    };
    let store_floating_window = cfg!(all(target_os = "macos", not(feature = "self-update")));
    let (window_width, window_height) = if store_floating_window {
        // Store builds remove the CSS shadow canvas and use a public NSWindow
        // shadow around the rounded content mask instead.
        (228.0, 78.0)
    } else {
        (248.0, 100.0)
    };
    let window_builder = WebviewWindowBuilder::new(app, "mini", WebviewUrl::App(url.into()))
        .title(DESKTOP_BRAND_NAME)
        // 窗口比卡片本身大一圈，多出来的部分纯粹是留给投影的画布：窗口无边框且
        // 透明，投影由页面的 CSS 画，超出窗口的部分会被**硬生生截断**——截断的
        // 软阴影正是"廉价"的来源。
        //
        // ⚠️ 留白要按 `offset + 1.5×blur + spread` 算，不是 `blur/2`。Chromium 的
        // box-shadow 用 sigma=blur/2 的高斯核，可见范围到 3σ，也就是 1.5 倍 blur。
        // 按 blur/2 算会短一大截：实测截断处背景 252、阴影还停在 246，肉眼就是
        // 一条直边。这一版的最大一层是 `0 3px 8px -3px`，需要 3+12-3=12pt，
        // 四周留白都比它宽。
        //
        // 卡片仍是 228x78（与最初版本一致），留白见 MiniCountdown.tsx：
        // 左右各 10pt、上 8pt、下 14pt。改这里就要同步改那边，否则卡片会变形。
        .inner_size(window_width, window_height)
        .min_inner_size(window_width, window_height)
        .max_inner_size(window_width, window_height)
        .resizable(false)
        .maximizable(false)
        .fullscreen(false)
        .decorations(false);
    // 无边框窗口若不透明，CSS 圆角只会把窗口自己的底色露在四个角上，
    // 看起来就是个直角方块。透明之后圆角和投影才由页面说了算。
    // Mac App Store 渠道不启用这个私有 API；MAS-P1 会用公开 AppKit 面板替代
    // 商店版的 WebView 悬浮窗，不能在这里偷偷把 feature 加回来。
    //
    // ⚠️ cfg 条件必须与 Tauri 给 `transparent()` 本身设的门完全一致，不能只写
    // `feature = "macos-private-api"`：透明窗只有 **macOS** 需要私有 API，而
    // `macos-private-api` 是全局默认 feature，微软商店版同样用
    // `--no-default-features` 构建。只按 feature 判断会让 Windows MSIX 的迷你窗
    // 丢掉透明度，变成一个 248x100 的不透明直角矩形。
    #[cfg(any(not(target_os = "macos"), feature = "macos-private-api"))]
    let window_builder = window_builder.transparent(true);
    let window = window_builder
        .shadow(store_floating_window)
        .always_on_top(always_on_top)
        .skip_taskbar(true)
        .visible(false)
        .build()?;

    #[cfg(target_os = "windows")]
    pin_webview_to_monitor_dpi(&window);

    #[cfg(all(target_os = "macos", not(feature = "self-update")))]
    if let Ok(ns_window) = window.ns_window() {
        native_mini::configure_store_floating_window(ns_window);
    }

    if let Some(position) = store
        .get(MINI_POSITION_KEY)
        .and_then(|value| serde_json::from_value::<MiniPosition>(value).ok())
    {
        let intersects_a_monitor =
            window
                .available_monitors()
                .unwrap_or_default()
                .iter()
                .any(|monitor| {
                    let origin = monitor.position();
                    let size = monitor.size();
                    // 只要求至少 40×40 px 仍在任一屏幕内；这样多显示器的合法负坐标
                    // 不会被误判，拔掉外接屏后完全落在屏外的旧位置则会被修复。
                    position.x + 40 > origin.x
                        && position.y + 40 > origin.y
                        && position.x < origin.x + size.width as i32
                        && position.y < origin.y + size.height as i32
                });
        if intersects_a_monitor {
            let _ = window.set_position(PhysicalPosition::new(position.x, position.y));
        } else {
            let _ = window.move_window(Position::BottomRight);
        }
    } else {
        let _ = window.move_window(Position::BottomRight);
    }

    let handle = window.clone();
    let app_handle = app.clone();
    window.on_window_event(move |event| match event {
        WindowEvent::CloseRequested { api, .. } => {
            api.prevent_close();
            let _ = handle.hide();
        }
        WindowEvent::Moved(position) => {
            if let Ok(store) = desktop_store(&app_handle) {
                store.set(
                    MINI_POSITION_KEY,
                    serde_json::to_value(MiniPosition {
                        x: position.x,
                        y: position.y,
                    })
                    .expect("mini window position should serialize"),
                );
            }
        }
        #[cfg(target_os = "windows")]
        WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
            pin_webview_to_monitor_dpi_with_scale(&handle, *scale_factor);
        }
        _ => {}
    });

    Ok(())
}

#[tauri::command]
fn get_mini_window_settings(app: AppHandle) -> Result<MiniWindowSettings, String> {
    let always_on_top = desktop_store(&app)?
        .get(MINI_ALWAYS_ON_TOP_KEY)
        .and_then(|value| value.as_bool())
        .unwrap_or(true);

    Ok(MiniWindowSettings {
        platform: platform_name(),
        always_on_top,
    })
}

#[tauri::command]
fn set_mini_always_on_top(app: AppHandle, always_on_top: bool) -> Result<(), String> {
    #[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
    if mini_window_enabled() {
        let window = app
            .get_webview_window("mini")
            .ok_or_else(|| "mini window is unavailable".to_string())?;
        window
            .set_always_on_top(always_on_top)
            .map_err(|error| error.to_string())?;
        let store = desktop_store(&app)?;
        store.set(MINI_ALWAYS_ON_TOP_KEY, always_on_top);
        return Ok(());
    }

    let _ = (app, always_on_top);
    Ok(())
}

#[tauri::command]
fn toggle_mini_timer(app: AppHandle) {
    toggle_mini_window(&app);
}

#[tauri::command]
fn toggle_floating_timer(app: AppHandle) {
    toggle_floating_window(&app);
}

#[tauri::command]
fn hide_mini_timer(app: AppHandle) {
    hide_mini_window(&app);
}

/// Windows 迷你窗点击后唤起主窗口：显示、取消最小化并聚焦。
#[tauri::command]
fn show_main_window(app: AppHandle) {
    focus_main_window(&app);
}

/// 迷你窗工具条上的「主窗口」按钮：显示 ↔ 隐藏来回切。
///
/// 不能复用 toggle_main_window：那个是给全局快捷键写的，要求主窗口「可见
/// 且已聚焦」才收起。从迷你窗点按钮时焦点在迷你窗上，主窗口永远不满足
/// 「已聚焦」，于是每次都走到显示分支，按钮就成了单向的。
///
/// 最小化的窗口在 macOS 上仍报告 visible，所以要单独排除，否则从 Dock
/// 最小化状态点这个按钮会「隐藏」一个本来就看不见的窗口。
#[tauri::command]
fn toggle_main_window_visibility(app: AppHandle) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    let showing = window.is_visible().unwrap_or(false) && !window.is_minimized().unwrap_or(false);
    if showing {
        let _ = window.hide();
    } else {
        focus_main_window(&app);
    }
}

/// 迷你窗（原生面板或 WebView 版）上的眼睛按钮统一走这里翻转 hide_earnings。
///
/// 写回 store 后，store 插件会广播 `store://change`；主窗口和迷你窗都通过
/// `subscribeToDesktopCountdown` 订阅它，因此两边会同时更新。
fn flip_hide_earnings(app: &AppHandle) {
    let mut state = read_countdown_state(app);
    state.hide_earnings = !state.hide_earnings;
    if let Ok(store) = desktop_store(app) {
        if let Ok(value) = serde_json::to_value(&state) {
            store.set(COUNTDOWN_KEY, value);
        }
    }
}

#[tauri::command]
fn toggle_salary_visibility(app: AppHandle) {
    flip_hide_earnings(&app);
}

/// Windows 自绘标题栏上的最小化按钮。
#[tauri::command]
fn minimize_main_window(app: AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.minimize();
    }
}

/// Windows 自绘标题栏上的关闭按钮。隐藏而不退出——和点原生标题栏的 X
/// 一样（那条路径由 CloseRequested 拦下），真正的退出只在托盘菜单里。
#[tauri::command]
fn hide_main_window(app: AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

/// 迷你窗工具条上的皮肤切换。
#[tauri::command]
fn toggle_mini_skin(app: AppHandle) -> Result<(), String> {
    let store = desktop_store(&app)?;
    let mut state = match store.get(COUNTDOWN_KEY) {
        Some(value) => serde_json::from_value::<CountdownState>(value)
            .map_err(|error| error.to_string())?
            .migrate_legacy(),
        None => CountdownState::default(),
    };
    // 木鱼是默认皮肤，空字符串也算木鱼，所以判据是「是不是简约」。
    state.mini_skin = if state.mini_skin == "standard" {
        "woodfish".into()
    } else {
        "standard".into()
    };
    let value = serde_json::to_value(&state).map_err(|error| error.to_string())?;
    store.set(COUNTDOWN_KEY, value);
    store.save().map_err(|error| error.to_string())
}

/// 迷你窗工具条上的声音开关。与眼睛按钮同理：由 Rust 改写 store，
/// 主窗口的设置项通过订阅收到同一份状态，两处不会各说各话。
#[tauri::command]
fn toggle_woodfish_sound(app: AppHandle) -> Result<(), String> {
    let store = desktop_store(&app)?;
    let mut state = match store.get(COUNTDOWN_KEY) {
        Some(value) => serde_json::from_value::<CountdownState>(value)
            .map_err(|error| error.to_string())?
            .migrate_legacy(),
        None => CountdownState::default(),
    };
    state.woodfish_sound_enabled = !state.woodfish_sound_enabled;
    let value = serde_json::to_value(&state).map_err(|error| error.to_string())?;
    store.set(COUNTDOWN_KEY, value);
    store.save().map_err(|error| error.to_string())
}

fn read_global_shortcut_settings(app: &AppHandle) -> GlobalShortcutSettings {
    desktop_store(app)
        .ok()
        .and_then(|store| store.get(GLOBAL_SHORTCUT_SETTINGS_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn persist_global_shortcut_settings(
    app: &AppHandle,
    settings: &GlobalShortcutSettings,
) -> Result<(), String> {
    let store = desktop_store(app)?;
    let value = serde_json::to_value(settings).map_err(|error| error.to_string())?;
    store.set(GLOBAL_SHORTCUT_SETTINGS_KEY, value);
    store.save().map_err(|error| error.to_string())
}

#[cfg(desktop)]
fn parse_global_shortcut(accelerator: &str) -> Result<Shortcut, String> {
    let shortcut = accelerator
        .parse::<Shortcut>()
        .map_err(|error| error.to_string())?;
    if shortcut.mods.is_empty() {
        return Err("global shortcut requires at least one modifier".into());
    }
    Ok(shortcut)
}

#[tauri::command]
fn get_global_shortcut_settings(app: AppHandle) -> GlobalShortcutSettings {
    read_global_shortcut_settings(&app)
}

/// 原子替换全局快捷键：新组合键冲突时旧快捷键仍保持可用；Store 写入失败时，
/// 系统注册状态也会回滚，避免界面配置与真正生效的按键不一致。
#[tauri::command]
fn update_global_shortcut_settings(
    app: AppHandle,
    enabled: bool,
    accelerator: String,
) -> Result<GlobalShortcutSettings, String> {
    #[cfg(desktop)]
    {
        let accelerator = accelerator.trim().to_string();
        let requested_shortcut = parse_global_shortcut(&accelerator)?;
        let previous = read_global_shortcut_settings(&app);
        let previous_shortcut = parse_global_shortcut(&previous.accelerator).unwrap_or_else(|_| {
            DEFAULT_GLOBAL_SHORTCUT
                .parse()
                .expect("valid default shortcut")
        });
        let requested = GlobalShortcutSettings {
            enabled,
            accelerator,
        };
        let manager = app.global_shortcut();
        let same_shortcut = previous_shortcut == requested_shortcut;
        let old_registered = manager.is_registered(previous_shortcut);
        let mut registered_new = false;
        let mut unregistered_old = false;

        if requested.enabled && !manager.is_registered(requested_shortcut) {
            manager
                .register(requested_shortcut)
                .map_err(|error| format!("could not register global shortcut: {error}"))?;
            registered_new = true;
        }

        if previous.enabled && !requested.enabled && old_registered {
            manager
                .unregister(previous_shortcut)
                .map_err(|error| format!("could not unregister global shortcut: {error}"))?;
            unregistered_old = true;
        } else if previous.enabled && requested.enabled && !same_shortcut && old_registered {
            if let Err(error) = manager.unregister(previous_shortcut) {
                if registered_new {
                    let _ = manager.unregister(requested_shortcut);
                }
                return Err(format!("could not replace global shortcut: {error}"));
            }
            unregistered_old = true;
        }

        if let Err(error) = persist_global_shortcut_settings(&app, &requested) {
            if registered_new {
                let _ = manager.unregister(requested_shortcut);
            }
            if unregistered_old {
                let _ = manager.register(previous_shortcut);
            }
            return Err(error);
        }

        Ok(requested)
    }

    #[cfg(not(desktop))]
    {
        let _ = (app, enabled, accelerator);
        Err("global shortcuts are unavailable on this platform".into())
    }
}

/// 直连 GitHub 下载安装包在中国大陆常常很慢甚至超时。这是**直连失败之后**
/// 才会用到的备用通道：一份内容相同、但 URL 带反代前缀的清单。
///
/// 完整性不受影响：更新包由 minisign 签名，公钥编译在二进制里，校验发生在
/// 下载之后、安装之前。反代即使返回被篡改的安装包也会在这一步被拒绝，
/// 所以引入第三方反代不会变成供应链问题。
///
/// 前端展示用的主机名在 lib/desktop-state.ts 里有一份副本，改这里要同步。
#[cfg(feature = "self-update")]
const MIRROR_UPDATER_ENDPOINT: &str ="https://gh-proxy.com/https://github.com/ififi2017/Off-Work-Countdown/releases/latest/download/latest-cn.json";

/// Partner Center 分配的商店产品 ID。与 src-tauri/msstore/Package.appxmanifest
/// 的 Identity 同属一份不可分割的商店身份，改一个就要核对另一个。
///
/// 产品上线之前这个深链打不开任何页面——商店对未发布的产品不提供 pdp 链接。
/// 这不是 bug，P3 之后自然生效。
#[cfg(target_os = "windows")]
const MICROSOFT_STORE_PRODUCT_ID: &str = "9PM0HJ2PP2LJ";

#[cfg(all(target_os = "macos", not(feature = "self-update")))]
fn widget_snapshot_contains_sensitive_data(value: &serde_json::Value) -> bool {
    const SENSITIVE_KEYS: &[&str] = &[
        "salary",
        "salaryamount",
        "dailysalary",
        "hourlyrate",
        "earnings",
        "income",
        "wage",
    ];
    match value {
        serde_json::Value::Object(object) => object.iter().any(|(key, value)| {
            SENSITIVE_KEYS.contains(&key.to_ascii_lowercase().as_str())
                || widget_snapshot_contains_sensitive_data(value)
        }),
        serde_json::Value::Array(values) => {
            values.iter().any(widget_snapshot_contains_sensitive_data)
        }
        _ => false,
    }
}

/// 接收前端业务层已经投影好的时间线并原子写入 App Group。这里只验证传输契约和
/// 隐私边界，不在 Rust 中推导班次、午休、跨日或加班规则。
#[cfg(all(target_os = "macos", not(feature = "self-update")))]
#[tauri::command]
fn write_widget_snapshot(snapshot_json: String) -> Result<(), String> {
    const MAX_WIDGET_SNAPSHOT_BYTES: usize = 256 * 1024;
    if snapshot_json.is_empty() || snapshot_json.len() > MAX_WIDGET_SNAPSHOT_BYTES {
        return Err("the Widget snapshot payload size is invalid".into());
    }
    let snapshot: serde_json::Value =
        serde_json::from_str(&snapshot_json).map_err(|error| error.to_string())?;
    if snapshot
        .get("schemaVersion")
        .and_then(|value| value.as_u64())
        != Some(1)
    {
        return Err("the Widget snapshot schema is unsupported".into());
    }
    if widget_snapshot_contains_sensitive_data(&snapshot) {
        return Err("the Widget snapshot contains a sensitive earnings field".into());
    }
    macos_widget::write_snapshot(&snapshot_json)
}

/// 通过镜像清单重新检查、下载并安装更新。
///
/// 没法复用前端的 updater 插件调用：JS 侧的 `check()` 只有 `proxy`（HTTP 代理）
/// 参数，而 gh-proxy 是 URL 前缀重写，两者不是一回事；而且安装包的真实地址
/// 来自清单内部，光把清单换掉不够——必须整条链路都走镜像，这只有 Rust 侧的
/// `UpdaterBuilder::endpoints()` 能在运行时做到。
#[cfg(feature = "self-update")]
#[tauri::command]
async fn install_update_via_mirror(app: AppHandle) -> Result<(), String> {
    use tauri_plugin_updater::UpdaterExt;

    let endpoint: tauri::Url = MIRROR_UPDATER_ENDPOINT
        .parse()
        .map_err(|error| format!("invalid mirror endpoint: {error}"))?;
    let updater = app
        .updater_builder()
        .endpoints(vec![endpoint])
        .map_err(|error| error.to_string())?
        .build()
        .map_err(|error| error.to_string())?;
    let update = updater
        .check()
        .await
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "mirror manifest reports no available update".to_string())?;
    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(|error| error.to_string())
}

/// 商店版的「检查更新」入口：打开自己的商店详情页，由商店负责更新。
///
/// 见 docs/PLAN-MSSTORE.md 决策 2。走 Rust 侧的 opener 而不是前端的
/// `openUrl`，与 `open_notification_settings` 同样的理由：`ms-windows-store:`
/// 不是 http scheme，前端那条路要在 capability 白名单里逐条声明。
#[cfg(target_os = "windows")]
#[tauri::command]
fn open_microsoft_store_listing(app: AppHandle) -> Result<(), String> {
    let url = format!("ms-windows-store://pdp/?productid={MICROSOFT_STORE_PRODUCT_ID}");
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|error| error.to_string())
}

/// 自启动的真实状态。比一个 bool 多一个 `locked`，因为 MSIX 那条路上「关着」
/// 有两种含义：应用自己没开，和用户在「设置 → 应用 → 启动」里关掉了——后者
/// 应用无权改回来，`RequestEnableAsync` 会直接返回原状态。
///
/// 两种渠道都返回这个结构，前端因此不必知道自己跑在哪条实现上；注册表那条路
/// 永远 `locked: false`，因为它确实想开就能开。
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
struct AutostartState {
    enabled: bool,
    locked: bool,
}

#[cfg(all(target_os = "macos", not(feature = "run-key-autostart")))]
fn macos_login_item_state(status: i32) -> Result<AutostartState, String> {
    match status {
        // SMAppServiceStatusEnabled
        1 => Ok(AutostartState {
            enabled: true,
            locked: false,
        }),
        // SMAppServiceStatusRequiresApproval. The app cannot approve itself;
        // the user controls this in System Settings → General → Login Items.
        2 => Ok(AutostartState {
            enabled: false,
            locked: true,
        }),
        // SMAppServiceStatusNotFound。对 `mainAppService` 而言这**不是**错误：
        // 从未注册过的应用首次读取就是 3，而不是 0（实测：全新 bundle 读到 3，
        // register 后变 1，unregister 后才变 0）。之前把它当错误返回，导致每次
        // 全新安装后设置页都挂着一条「桌面设置更新失败」——而用户手动点一下开关
        // 注册成功后它就消失了，正是这个原因。
        //
        // 0 和 3 对用户是同一件事：没开机自启，且可以打开。
        0 | 3 => Ok(AutostartState {
            enabled: false,
            locked: false,
        }),
        // ObjC 侧用负数区分两种完全不同的失败，之前一起落进这个分支，注册失败会被
        // 报成「系统版本不支持」——看到这条消息的人会去查 macOS 版本，方向就错了。
        -1 => Err("SMAppService requires macOS 13 or later".into()),
        -2 => Err(
            "macOS refused to register the login item; open System Settings → General → Login Items to check"
                .into(),
        ),
        other => Err(format!("unexpected SMAppService status: {other}")),
    }
}

/// manifest 里 `<uap5:StartupTask TaskId="...">` 的 TaskId，必须逐字一致，
/// 对不上的表现是 `StartupTask::GetAsync` 抛异常而不是返回一个禁用状态。
#[cfg(all(target_os = "windows", not(feature = "run-key-autostart")))]
const STARTUP_TASK_ID: &str = "OffWorkCountdownStartup";

#[cfg(all(target_os = "windows", not(feature = "run-key-autostart")))]
fn startup_task() -> Result<windows::ApplicationModel::StartupTask, String> {
    use windows::core::HSTRING;

    windows::ApplicationModel::StartupTask::GetAsync(&HSTRING::from(STARTUP_TASK_ID))
        .and_then(|op| op.get())
        // 没有包标识时（比如把商店渠道的 exe 直接双击运行）这里必然失败。
        // 保留原始错误：它是排查 TaskId 写错和「没跑在包里」的唯一线索。
        .map_err(|error| format!("startup task {STARTUP_TASK_ID} is unavailable: {error}"))
}

#[cfg(all(target_os = "windows", not(feature = "run-key-autostart")))]
fn read_startup_task_state() -> Result<AutostartState, String> {
    use windows::ApplicationModel::StartupTaskState;

    let state = startup_task()?.State().map_err(|error| error.to_string())?;
    Ok(match state {
        StartupTaskState::Enabled => AutostartState {
            enabled: true,
            locked: false,
        },
        // 策略打开的同样锁着：应用改不动，只是方向相反。
        StartupTaskState::EnabledByPolicy => AutostartState {
            enabled: true,
            locked: true,
        },
        StartupTaskState::DisabledByUser | StartupTaskState::DisabledByPolicy => AutostartState {
            enabled: false,
            locked: true,
        },
        // Disabled 以及将来可能新增的取值都按「关着但能开」处理。
        _ => AutostartState {
            enabled: false,
            locked: false,
        },
    })
}

/// 读自启动状态。两条实现的分界就是渠道的分界，前端只看到同一个命令。
#[tauri::command]
async fn get_autostart_state(app: AppHandle) -> Result<AutostartState, String> {
    #[cfg(feature = "run-key-autostart")]
    {
        use tauri_plugin_autostart::ManagerExt;

        let enabled = app
            .autolaunch()
            .is_enabled()
            .map_err(|error| error.to_string())?;
        // 注册表 Run 键任何时候都能改，没有"被系统锁住"这回事。
        Ok(AutostartState {
            enabled,
            locked: false,
        })
    }
    #[cfg(all(target_os = "windows", not(feature = "run-key-autostart")))]
    {
        let _ = app;
        read_startup_task_state()
    }
    #[cfg(all(target_os = "macos", not(feature = "run-key-autostart")))]
    {
        let _ = app;
        macos_login_item_state(native_mini::login_item_status())
    }
    #[cfg(all(
        not(any(target_os = "windows", target_os = "macos")),
        not(feature = "run-key-autostart")
    ))]
    {
        let _ = app;
        Err("autostart is unavailable in this build".into())
    }
}

/// 写自启动状态，并把**写完之后的真实状态**回给前端。
///
/// 返回值不是入参的回声：MSIX 那条路上用户可能已经在系统设置里锁死了这个开关，
/// 这时请求打开不会报错，只是什么都不会发生。前端照着返回值渲染，才不会出现
/// 「开关是开的、开机却不启动」——那正是 P2 实测到的商店版旧行为。
#[tauri::command]
async fn set_autostart_enabled(app: AppHandle, enabled: bool) -> Result<AutostartState, String> {
    #[cfg(feature = "run-key-autostart")]
    {
        use tauri_plugin_autostart::ManagerExt;

        let manager = app.autolaunch();
        if enabled {
            manager.enable().map_err(|error| error.to_string())?;
        } else {
            manager.disable().map_err(|error| error.to_string())?;
        }
        let enabled = manager.is_enabled().map_err(|error| error.to_string())?;
        Ok(AutostartState {
            enabled,
            locked: false,
        })
    }
    #[cfg(all(target_os = "windows", not(feature = "run-key-autostart")))]
    {
        let _ = app;
        let task = startup_task()?;
        if enabled {
            // 返回值就是请求之后的真实状态：被用户关掉时它仍然是 DisabledByUser，
            // 不会报错。把它当成「开成功了」正是决策 3 要避免的那种假开关。
            task.RequestEnableAsync()
                .and_then(|op| op.get())
                .map_err(|error| error.to_string())?;
        } else {
            task.Disable().map_err(|error| error.to_string())?;
        }
        read_startup_task_state()
    }
    #[cfg(all(target_os = "macos", not(feature = "run-key-autostart")))]
    {
        let _ = app;
        let current = native_mini::login_item_status();
        if (enabled && matches!(current, 1 | 2)) || (!enabled && current == 0) {
            return macos_login_item_state(current);
        }
        macos_login_item_state(native_mini::set_login_item_enabled(enabled))
    }
    #[cfg(all(
        not(any(target_os = "windows", target_os = "macos")),
        not(feature = "run-key-autostart")
    ))]
    {
        let _ = (app, enabled);
        Err("autostart is unavailable in this build".into())
    }
}

#[tauri::command]
fn update_desktop_menus(app: AppHandle, labels: DesktopMenuLabels) -> Result<(), String> {
    let tray_menu = build_tray_menu(&app, &labels).map_err(|error| {
        log::error!("failed to build localized tray menu: {error}");
        error.to_string()
    })?;
    let tray = app
        .tray_by_id("main")
        .ok_or_else(|| "main tray icon is unavailable".to_string())?;
    tray.set_menu(Some(tray_menu)).map_err(|error| {
        log::error!("failed to install localized tray menu: {error}");
        error.to_string()
    })?;

    #[cfg(target_os = "macos")]
    if let Err(error) = set_macos_application_menu(&app, &labels) {
        log::error!("failed to localize macOS application menu: {error}");
        return Err(error.to_string());
    }

    Ok(())
}

#[tauri::command]
fn clear_desktop_countdown_display(app: AppHandle) {
    if let Some(tray) = app.tray_by_id("main") {
        #[cfg(target_os = "macos")]
        let _ = tray.set_title(Some(""));
        let _ = tray.set_tooltip(Some(DESKTOP_BRAND_NAME));
    }
}

#[tauri::command]
fn open_notification_settings(app: AppHandle) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension";
    #[cfg(target_os = "windows")]
    let url = "ms-settings:notifications";
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    return Err("notification settings shortcut is unavailable on this platform".into());

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|error| error.to_string())
}

/// WebView2 默认的 RasterizationScale = 显示器 DPI ×「设置 → 辅助功能 → 文本大小」。
/// 主窗口和悬浮窗都是按逻辑像素排的固定工具窗，系统字号会把整块 UI 同比放大。
///
/// 关掉自动跟随后，只写入当前窗口的显示器 DPI（`scale_factor`）；换屏时再跟着
/// `ScaleFactorChanged` 更新。125%/150% 的显示器缩放仍然有效，只是不再吃字号。
#[cfg(target_os = "windows")]
fn pin_webview_to_monitor_dpi(window: &tauri::WebviewWindow) {
    let scale = window.scale_factor().unwrap_or(1.0);
    pin_webview_to_monitor_dpi_with_scale(window, scale);
}

#[cfg(target_os = "windows")]
fn pin_webview_to_monitor_dpi_with_scale(window: &tauri::WebviewWindow, scale: f64) {
    if let Err(error) = window.with_webview(move |webview| {
        use webview2_com::Microsoft::Web::WebView2::Win32::ICoreWebView2Controller3;
        use windows::core::Interface;

        // SAFETY: wry 在控制器创建完成后才把 PlatformWebview 交给 `with_webview`。
        // ICoreWebView2Controller3 从 WebView2 1.0.774.44 起可用；QueryInterface
        // 失败只跳过，不保留任何 COM 指针越过这个闭包。
        unsafe {
            let Ok(controller) = Interface::cast::<ICoreWebView2Controller3>(&webview.controller())
            else {
                return;
            };
            let _ = controller.SetShouldDetectMonitorScaleChanges(false);
            let _ = controller.SetRasterizationScale(scale);
        }
    }) {
        log::warn!("failed to pin WebView2 rasterization scale: {error}");
    }
}

/// WebView2 不在时，给出一句能照着做的话，而不是让用户对着一个白窗口。
///
/// 三条路都查过了：MSIX 的 `win32dependencies:ExternalDependency` 只有 App
/// Installer 认，商店安装会**静默忽略**它（而且打包工具不校验，看起来像生效了）；
/// 内嵌 Fixed Version 要多背 250MB，对一个 5MB 的应用不成比例。剩下的就是微软
/// 分发文档给的第二个建议——先检测，再把用户引到官方下载页。
///
/// NSIS/MSI 那条线已经由 Tauri 默认的 `downloadBootstrapper` 覆盖，但那依赖
/// 安装时有网，也管不了装完之后运行时被卸载；MSIX 那条线则完全没有别的防线。
#[cfg(target_os = "windows")]
fn ensure_webview2_runtime() {
    use std::os::windows::process::CommandExt;
    use windows::core::w;
    use windows::Win32::UI::WindowsAndMessaging::{
        MessageBoxW, IDOK, MB_ICONINFORMATION, MB_OKCANCEL,
    };

    if tauri::webview_version().is_ok() {
        return;
    }

    // 这一步发生在窗口创建之前，前端和 i18n 都还没起来，拿不到界面语言。
    // 与长内容页同样的取舍：只做中英双语，而不是猜一个可能猜错的。
    let choice = unsafe {
        MessageBoxW(
            None,
            w!("DoneAt draws its window with Microsoft Edge WebView2. Most Windows PCs already include it, and this one does not have it yet.\n\n\
                It is a small, free component from Microsoft and takes about a minute to install. Select OK and we will open the download page for you.\n\n\
                DoneAt 用 Microsoft Edge WebView2 绘制界面。大多数 Windows 电脑都自带，这台还没有。\n\n\
                它是微软提供的免费组件，安装大约需要一分钟。点「确定」，我们帮你打开下载页面。"),
            w!("DoneAt"),
            MB_OKCANCEL | MB_ICONINFORMATION,
        )
    };

    if choice == IDOK {
        // 用 cmd start 而不是 ShellExecuteW：这段代码在 macOS 上编译不了，
        // 少碰一个没法本地验证的 Win32 签名，就少一处只有 CI 才会发现的错。
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let _ = std::process::Command::new("cmd")
            .args([
                "/C",
                "start",
                "",
                "https://developer.microsoft.com/microsoft-edge/webview2/consumer/",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn();
    }

    std::process::exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // 必须在 Builder 之前：WebView2 缺失时窗口根本创建不出来，等到那一步
    // 用户看到的就是一个白框，或者干脆什么都没有。
    #[cfg(target_os = "windows")]
    ensure_webview2_runtime();

    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_opener::init());

    // 商店版由微软商店负责更新，自更新链路整体编译掉（见
    // docs/PLAN-MSSTORE.md 决策 2）。process 插件只被更新后的 relaunch
    // 用到，一并跟着走。
    #[cfg(feature = "self-update")]
    {
        builder = builder
            .plugin(tauri_plugin_process::init())
            .plugin(tauri_plugin_updater::Builder::new().build());
    }

    // 单实例必须最先注册：它要在任何窗口创建之前拦下第二个进程，
    // 否则第二次启动会先建好窗口再被关掉，用户能看到窗口一闪。
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            focus_main_window(app);
        }));
        builder = builder.plugin(tauri_plugin_notification::init());
        // 商店渠道整条注册表 Run 键的路都编译掉：在 MSIX 容器里它的写入会被
        // 重定向进包的虚拟注册表，Windows 根本看不到，表现成一个「开关是开的、
        // 开机却不启动」的假开关。见决策 3 与 P2 实测。
        #[cfg(feature = "run-key-autostart")]
        {
            builder = builder.plugin(tauri_plugin_autostart::init(
                tauri_plugin_autostart::MacosLauncher::LaunchAgent,
                None,
            ));
        }
        builder = builder.plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state == ShortcutState::Pressed {
                        toggle_main_window(app);
                    }
                })
                .build(),
        );
    }

    builder
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_positioner::init())
        .invoke_handler(tauri::generate_handler![
            get_mini_window_settings,
            set_mini_always_on_top,
            toggle_mini_timer,
            toggle_floating_timer,
            hide_mini_timer,
            show_main_window,
            toggle_main_window_visibility,
            minimize_main_window,
            hide_main_window,
            toggle_salary_visibility,
            toggle_woodfish_sound,
            toggle_mini_skin,
            get_global_shortcut_settings,
            update_global_shortcut_settings,
            #[cfg(feature = "self-update")]
            install_update_via_mirror,
            #[cfg(target_os = "windows")]
            open_microsoft_store_listing,
            #[cfg(all(target_os = "macos", not(feature = "self-update")))]
            write_widget_snapshot,
            #[cfg(all(target_os = "macos", not(feature = "self-update")))]
            get_desktop_store_path,
            get_autostart_state,
            set_autostart_enabled,
            update_desktop_menus,
            clear_desktop_countdown_display,
            open_notification_settings
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // Rust 先加载 Store，使随后来自前端的 load() 与后台线程共享同一个实例。
            let _ = desktop_store(app.handle())
                .map_err(|error| std::io::Error::other(error.to_string()))?;
            #[cfg(desktop)]
            {
                let shortcut_settings = read_global_shortcut_settings(app.handle());
                if shortcut_settings.enabled {
                    if let Err(error) = app
                        .global_shortcut()
                        .register(shortcut_settings.accelerator.as_str())
                    {
                        // 快捷键冲突不应阻止应用启动；用户仍可用 Dock/任务栏与托盘唤起。
                        log::warn!("failed to register global shortcut: {error}");
                    }
                }
            }
            setup_tray(app.handle())?;
            #[cfg(target_os = "macos")]
            {
                set_macos_application_menu(app.handle(), &DesktopMenuLabels::default())?;
                APP_HANDLE.set(app.handle().clone()).ok();
                native_mini::on_effective_appearance_change(refresh_macos_tray_icon);
                native_mini::initialize();
                // 本地 UI 验收可显式要求启动时展示原生面板；正式包未设置该
                // 环境变量，因此仍只在用户点击托盘图标后出现。
                if cfg!(debug_assertions) && std::env::var_os("OWC_SHOW_NATIVE_MINI").is_some() {
                    native_mini::toggle();
                }
            }
            #[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
            if mini_window_enabled() {
                setup_mini_window(app.handle())?;
                if cfg!(debug_assertions) && std::env::var_os("OWC_SHOW_FLOATING_MINI").is_some() {
                    toggle_floating_window(app.handle());
                }
            }
            start_tray_timer(app.handle().clone());

            // Windows 的原生标题栏用的是系统配色，和应用内的玻璃卡片对不上，
            // 顶着一条灰白（或纯黑）的横条很出戏。这里去掉它，改由前端自绘；
            // 阴影要显式保留，否则无边框窗口会和桌面糊在一起。
            #[cfg(target_os = "windows")]
            if let Some(window) = app.get_webview_window("main") {
                // ⚠️ 关装饰会把原本属于标题栏的那条高度让给客户区：窗口外框不动，
                // 内容区凭空长高约 30pt，tauri.conf.json 里写的 430x430 到了
                // Windows 上就成了 430x460。页面仍按 430 排版，多出来的空档摊在
                // 版面里，看起来就是「Windows 版留白比 macOS 多一圈」。
                //
                // 前后各读一次再还回去，而不是硬写 430——尺寸的唯一出处仍然是
                // tauri.conf.json，改那边不必记得回来同步这里。尺寸本来就没变时
                // 这是个 no-op。
                let inner_before = window.inner_size().ok();
                let _ = window.set_decorations(false);
                let _ = window.set_shadow(true);
                if let Some(size) = inner_before {
                    let _ = window.set_size(size);
                }
                pin_webview_to_monitor_dpi(&window);
            }

            // 关闭主窗口时隐藏而非退出。真正的退出走托盘菜单里的 Quit。
            if let Some(window) = app.get_webview_window("main") {
                let handle = window.clone();
                window.on_window_event(move |event| {
                    if let WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = handle.hide();
                    }
                    #[cfg(target_os = "windows")]
                    if let WindowEvent::ScaleFactorChanged { scale_factor, .. } = event {
                        pin_webview_to_monitor_dpi_with_scale(&handle, *scale_factor);
                    }
                });
            }

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            // macOS：应用已在运行时点击 Dock 图标（或再次打开）不会新建进程，
            // 因此单实例插件不会触发。
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { .. } = event {
                focus_main_window(app);
            }
            #[cfg(not(target_os = "macos"))]
            {
                let _ = (app, event);
            }
        });
}

#[cfg(test)]
mod reminder_tests {
    use super::*;

    // 这些用例只锁 Rust 侧的消费语义：跨越判定、有效期、跳拍间隔、折叠、去重。
    // 提醒的时刻与文案怎么算出来的属于 lib/reminders.ts，由那边的 vitest 覆盖。

    const REVISION: &str = "1:1000";

    fn milestone(percent: u8, at_ms: i64) -> ShiftReminder {
        ShiftReminder {
            id: format!("milestone:{percent}"),
            at_ms,
            collapse_group: Some("milestone".into()),
            title: Some("下班提醒".into()),
            body: Some(format!("到 {percent}% 了")),
            ..Default::default()
        }
    }

    fn muted(mut reminder: ShiftReminder) -> ShiftReminder {
        reminder.title = None;
        reminder.body = None;
        reminder
    }

    fn state(reminders: Vec<ShiftReminder>) -> CountdownState {
        CountdownState {
            segments: vec![ShiftSegment {
                start_at_ms: 0,
                end_at_ms: 1_000,
            }],
            planned_end_at_ms: 1_000,
            running: true,
            reminders,
            reminders_revision: REVISION.into(),
            ..Default::default()
        }
    }

    fn milestones() -> Vec<ShiftReminder> {
        vec![
            milestone(50, 500),
            milestone(75, 750),
            milestone(90, 900),
            milestone(95, 950),
            milestone(100, 1_000),
        ]
    }

    /// 走一拍：与托盘计时器里的顺序一致——先推进，再更新基线。
    fn tick(countdown: &CountdownState, marker: &mut ReminderMarker, now_ms: i64) -> Vec<String> {
        let (due, _) = advance_reminders(countdown, marker, now_ms);
        let ids = due.iter().map(|reminder| reminder.id.clone()).collect();
        marker.last_observed_ms = now_ms;
        ids
    }

    #[test]
    fn milestone_nodes_fire_once_in_order() {
        let countdown = state(milestones());
        let mut marker = ReminderMarker::default();

        // 第一拍只建立基线。
        assert!(tick(&countdown, &mut marker, 0).is_empty());
        assert_eq!(tick(&countdown, &mut marker, 500), vec!["milestone:50"]);
        assert!(tick(&countdown, &mut marker, 500).is_empty());
        assert_eq!(tick(&countdown, &mut marker, 750), vec!["milestone:75"]);
        assert_eq!(tick(&countdown, &mut marker, 900), vec!["milestone:90"]);
        assert_eq!(tick(&countdown, &mut marker, 950), vec!["milestone:95"]);
        assert_eq!(tick(&countdown, &mut marker, 1_000), vec!["milestone:100"]);
    }

    #[test]
    fn wakeups_emit_only_the_highest_new_milestone() {
        let countdown = state(milestones());
        let mut marker = ReminderMarker::default();
        tick(&countdown, &mut marker, 400);

        assert_eq!(tick(&countdown, &mut marker, 960), vec!["milestone:95"]);
        // 被折叠掉的三条同样记为已发，否则下一拍会重新算进候选。
        assert_eq!(
            marker.sent_ids,
            vec![
                "milestone:50".to_string(),
                "milestone:75".to_string(),
                "milestone:90".to_string(),
                "milestone:95".to_string(),
            ]
        );
        assert!(tick(&countdown, &mut marker, 970).is_empty());
    }

    #[test]
    fn muted_reminders_advance_the_marker_without_notifying() {
        // 通知档位关着的那些条目仍然出现在列表里，只是没有文案。它们必须照样
        // 被记为已发——否则班次进行到一半才打开开关，会立刻补弹一串历史提醒。
        let countdown = state(milestones().into_iter().map(muted).collect());
        let mut marker = ReminderMarker::default();
        tick(&countdown, &mut marker, 0);

        assert!(tick(&countdown, &mut marker, 800).is_empty());
        assert_eq!(marker.sent_ids.len(), 2);

        let audible = state(milestones());
        assert!(tick(&audible, &mut marker, 800).is_empty());
        assert_eq!(tick(&audible, &mut marker, 900), vec!["milestone:90"]);
    }

    #[test]
    fn a_new_revision_rebuilds_the_baseline_without_backfilling() {
        let countdown = state(milestones());
        let mut stale = ReminderMarker::default();

        // 班次已经走完才第一次看到这份列表：一条都不补。
        assert!(tick(&countdown, &mut stale, 1_001).is_empty());
        assert!(stale.sent_ids.is_empty());
        assert_eq!(stale.revision, REVISION);

        // 换一个班次时，旧的已发记录必须作废。
        let mut carried = ReminderMarker {
            model_version: REMINDER_MODEL_VERSION,
            revision: "1:9999".into(),
            sent_ids: vec!["milestone:50".into()],
            last_observed_ms: 400,
        };
        assert!(tick(&countdown, &mut carried, 600).is_empty());
        assert!(carried.sent_ids.is_empty());
        assert_eq!(carried.last_observed_ms, 600);
    }

    #[test]
    fn expired_reminders_are_marked_but_never_sent() {
        // 午休边界：设备睡到午休结束之后才醒，「午休开始了」已经失去语境。
        let countdown = state(vec![ShiftReminder {
            id: "breakStart:3000".into(),
            at_ms: 3_000,
            expires_at_ms: Some(4_000),
            title: Some("下班提醒".into()),
            body: Some("午休开始".into()),
            ..Default::default()
        }]);
        let mut marker = ReminderMarker::default();
        tick(&countdown, &mut marker, 2_900);

        assert!(tick(&countdown, &mut marker, 4_500).is_empty());
        assert_eq!(marker.sent_ids, vec!["breakStart:3000".to_string()]);
    }

    #[test]
    fn micro_break_reminders_skip_a_long_sleep_gap() {
        // 跳拍间隔看的是「上一拍到现在」，不是「距计划时刻多久」：设备睡着的
        // 那段时间用户并没有在工作，醒来后提示「该起来活动一下」是错的。
        let reminders = vec![ShiftReminder {
            id: "microBreak:0:5".into(),
            at_ms: 5_000,
            max_tick_gap_ms: Some(2_000),
            collapse_group: Some("microBreak:0".into()),
            title: Some("下班提醒".into()),
            body: Some("起来走走".into()),
            ..Default::default()
        }];

        let countdown = state(reminders);
        let mut normal = ReminderMarker::default();
        tick(&countdown, &mut normal, 4_500);
        assert_eq!(tick(&countdown, &mut normal, 5_000), vec!["microBreak:0:5"]);

        let mut slept = ReminderMarker::default();
        tick(&countdown, &mut slept, 1_000);
        assert!(tick(&countdown, &mut slept, 6_000).is_empty());
        assert_eq!(slept.sent_ids, vec!["microBreak:0:5".to_string()]);
    }

    #[test]
    fn clock_rollback_sends_nothing() {
        let countdown = state(milestones());
        let mut marker = ReminderMarker::default();
        tick(&countdown, &mut marker, 900);

        let (due, changed) = advance_reminders(&countdown, &mut marker, 100);
        assert!(due.is_empty());
        assert!(!changed);
    }

    #[test]
    fn quiet_ticks_do_not_ask_for_a_store_write() {
        // 每秒写一次 Store 没有意义。只有真正跨过提醒、或者列表换版时才落盘。
        let countdown = state(milestones());
        let mut marker = ReminderMarker::default();
        assert!(advance_reminders(&countdown, &mut marker, 0).1);
        marker.last_observed_ms = 0;

        assert!(!advance_reminders(&countdown, &mut marker, 100).1);
        marker.last_observed_ms = 100;
        assert!(advance_reminders(&countdown, &mut marker, 500).1);
    }

    #[test]
    fn an_empty_list_is_inert() {
        let countdown = state(Vec::new());
        let mut marker = ReminderMarker::default();
        tick(&countdown, &mut marker, 0);
        assert!(tick(&countdown, &mut marker, 10_000).is_empty());
    }
}

#[cfg(test)]
mod format_tests {
    use super::{
        advance_to_next_shift, countdown_metrics, countdown_pay_ratio, countdown_progress,
        format_remaining, parse_global_shortcut, CountdownState, GlobalShortcutSettings,
        ShiftSegment, ShiftTimelineState, DEFAULT_GLOBAL_SHORTCUT,
    };

    #[test]
    fn formats_remaining_time_without_business_logic() {
        assert_eq!(format_remaining(3_661_000), "1:01:01");
        assert_eq!(format_remaining(-1), "0:00:00");
        // 与小组件、主窗口一致地向下取整。上面两个用例都是整千毫秒，区分不出
        // ceil 与 floor——而正是那个差异让托盘恒定比小组件多一秒。
        assert_eq!(format_remaining(1_999), "0:00:01");
        assert_eq!(format_remaining(999), "0:00:00");
    }

    #[test]
    fn clamps_native_mini_progress_to_the_shift() {
        let state = CountdownState {
            segments: vec![ShiftSegment {
                start_at_ms: 1_000,
                end_at_ms: 2_000,
            }],
            planned_end_at_ms: 2_000,
            running: true,
            ..Default::default()
        };
        assert_eq!(countdown_progress(&state, 500), 0.0);
        assert_eq!(countdown_progress(&state, 1_500), 0.5);
        assert_eq!(countdown_progress(&state, 2_500), 1.0);
        assert_eq!(countdown_progress(&CountdownState::default(), 1_500), 0.0);
    }

    #[test]
    fn segmented_metrics_pause_between_work_periods() {
        let state = CountdownState {
            segments: vec![
                ShiftSegment {
                    start_at_ms: 1_000,
                    end_at_ms: 4_000,
                },
                ShiftSegment {
                    start_at_ms: 6_000,
                    end_at_ms: 11_000,
                },
            ],
            planned_end_at_ms: 11_000,
            running: true,
            ..Default::default()
        };

        assert_eq!(countdown_metrics(&state, 5_000), Some((5_000, 0.375)));
        assert_eq!(countdown_metrics(&state, 6_000), Some((5_000, 0.375)));
    }

    #[test]
    fn overtime_salary_uses_the_planned_hourly_rate() {
        // 加班是原时薪的线性延长：分母始终是计划时长，所以超出计划的部分让比例
        // 越过 1.0，而不是像进度那样被夹回 100%。
        let state = CountdownState {
            segments: vec![ShiftSegment {
                start_at_ms: 0,
                end_at_ms: 12_000,
            }],
            planned_end_at_ms: 10_000,
            overtime_end_at_ms: Some(12_000),
            running: true,
            ..Default::default()
        };
        assert!((countdown_pay_ratio(&state, 12_000) - 1.2).abs() < f64::EPSILON);
    }

    #[test]
    fn migrates_the_legacy_single_range_snapshot() {
        let state = CountdownState {
            legacy_start_at_ms: 1_000,
            legacy_end_at_ms: 2_000,
            running: true,
            ..Default::default()
        }
        .migrate_legacy();

        assert_eq!(state.segments.len(), 1);
        assert_eq!(state.segments[0].start_at_ms, 1_000);
        assert_eq!(state.segments[0].end_at_ms, 2_000);
        assert_eq!(state.planned_end_at_ms, 2_000);
        assert!(state.is_valid_shift());
    }

    #[test]
    fn rejects_a_planned_end_inside_a_segment_gap() {
        let state = CountdownState {
            segments: vec![
                ShiftSegment {
                    start_at_ms: 1_000,
                    end_at_ms: 4_000,
                },
                ShiftSegment {
                    start_at_ms: 6_000,
                    end_at_ms: 11_000,
                },
            ],
            planned_end_at_ms: 5_000,
            overtime_end_at_ms: Some(11_000),
            running: true,
            ..Default::default()
        };

        assert!(!state.is_valid_shift());
    }

    #[test]
    fn switches_only_to_a_live_frontend_supplied_next_shift() {
        // Rust 不推导下一班，只认前端投影好的快照，所以两条分支从同一份出发。
        fn shift_with_next() -> CountdownState {
            CountdownState {
                segments: vec![ShiftSegment {
                    start_at_ms: 0,
                    end_at_ms: 1_000,
                }],
                planned_end_at_ms: 1_000,
                running: true,
                next_shift: Some(ShiftTimelineState {
                    segments: vec![ShiftSegment {
                        start_at_ms: 2_000,
                        end_at_ms: 3_000,
                    }],
                    planned_end_at_ms: 3_000,
                    overtime_end_at_ms: None,
                }),
                ..Default::default()
            }
        }

        let mut countdown = shift_with_next();
        assert!(!advance_to_next_shift(&mut countdown, 1_500));
        assert!(advance_to_next_shift(&mut countdown, 2_100));
        assert_eq!(countdown.segments[0].start_at_ms, 2_000);
        assert!(countdown.next_shift.is_none());

        // 睡眠整段跨过了下一班：快照必须作废并停表，否则醒来会补发整班的提醒。
        let mut stale = shift_with_next();
        assert!(advance_to_next_shift(&mut stale, 4_000));
        assert!(!stale.running);
    }

    #[test]
    fn preserves_the_preferences_version_across_the_js_rust_store_bridge() {
        let state = CountdownState {
            _preferences_version: 1,
            ..Default::default()
        };
        let value = serde_json::to_value(&state).expect("state should serialize");
        assert_eq!(value["preferencesVersion"], 1);
        let restored: CountdownState =
            serde_json::from_value(value).expect("state should deserialize");
        assert_eq!(restored._preferences_version, 1);
    }

    #[test]
    fn global_shortcuts_require_a_modifier_and_keep_the_legacy_default() {
        let settings = GlobalShortcutSettings::default();
        assert!(settings.enabled);
        assert_eq!(settings.accelerator, DEFAULT_GLOBAL_SHORTCUT);
        assert!(parse_global_shortcut("Shift+KeyK").is_ok());
        assert!(parse_global_shortcut("KeyK").is_err());
        assert!(parse_global_shortcut("Shift").is_err());
    }
}

#[cfg(test)]
mod macos_tray_mark_tests {
    fn png_ihdr(bytes: &[u8]) -> (u32, u32, u8) {
        assert!(bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]));
        assert_eq!(&bytes[12..16], b"IHDR");
        let width = u32::from_be_bytes(bytes[16..20].try_into().expect("ihdr width"));
        let height = u32::from_be_bytes(bytes[20..24].try_into().expect("ihdr height"));
        let color_type = bytes[25];
        (width, height, color_type)
    }

    #[test]
    fn macos_tray_marks_are_transparent_and_not_the_app_icon() {
        let light = include_bytes!("../icons/macos-tray-mark.png");
        let dark = include_bytes!("../icons/macos-tray-mark-dark.png");
        let app_icon = include_bytes!("../icons/32x32.png");

        assert_ne!(light.as_slice(), app_icon.as_slice());
        assert_ne!(dark.as_slice(), app_icon.as_slice());
        assert_ne!(light.as_slice(), dark.as_slice());

        for bytes in [light.as_slice(), dark.as_slice()] {
            let (width, height, color_type) = png_ihdr(bytes);
            assert_eq!((width, height), (64, 64));
            // 6 = RGBA。菜单栏必须带着 alpha，否则又会铺出一块实心底。
            assert_eq!(color_type, 6);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn decoded_tray_marks_keep_transparent_corners() {
        for icon in [
            tauri::include_image!("icons/macos-tray-mark.png"),
            tauri::include_image!("icons/macos-tray-mark-dark.png"),
        ] {
            assert_eq!((icon.width(), icon.height()), (64, 64));
            let rgba = icon.rgba();
            assert_eq!(rgba[3], 0);
            assert_eq!(rgba[63 * 4 + 3], 0);
            assert_eq!(rgba[(63 * 64) * 4 + 3], 0);
            assert_eq!(rgba[rgba.len() - 1], 0);
            assert!(
                rgba.chunks(4).any(|pixel| pixel[3] > 200),
                "the mark itself must stay opaque"
            );
        }
    }
}
