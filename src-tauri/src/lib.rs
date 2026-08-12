use serde::{Deserialize, Serialize};
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

const STORE_PATH: &str = "desktop-state.json";
const COUNTDOWN_KEY: &str = "countdown";
const NOTIFICATION_MARKER_KEY: &str = "notificationMarker";
#[cfg(any(target_os = "windows", target_os = "macos", debug_assertions))]
const MINI_POSITION_KEY: &str = "miniPosition";
const MINI_ALWAYS_ON_TOP_KEY: &str = "miniAlwaysOnTop";
const GLOBAL_SHORTCUT_SETTINGS_KEY: &str = "globalShortcutSettings";
const DEFAULT_GLOBAL_SHORTCUT: &str = "CommandOrControl+Shift+O";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct GlobalShortcutSettings {
    enabled: bool,
    accelerator: String,
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

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum NotificationMode {
    #[default]
    Off,
    Simple,
    Milestones,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct NotificationMessages {
    milestone50: Vec<String>,
    milestone75: Vec<String>,
    milestone90: Vec<String>,
    milestone95: Vec<String>,
    milestone100: Vec<String>,
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
    previous_end == overtime_end_at_ms.unwrap_or(planned_end_at_ms)
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct CountdownState {
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
    notification_mode: Option<NotificationMode>,
    notification_title: String,
    notification_messages: NotificationMessages,
    /// 3.0.x 通知字段仅用于读取迁移，不再写入新 Store。
    #[serde(rename = "reminder", skip_serializing)]
    legacy_reminder: bool,
    show_salary: bool,
    hide_earnings: bool,
    daily_salary: Option<f64>,
    lang: String,
    countdown_not_started: String,
    next_shift_label: String,
    lunch_start_notification: String,
    lunch_end_notification: String,
    lunch_notification_enabled: bool,
    lunch_end_notification_enabled: bool,
    /// 迷你窗皮肤，可从悬浮窗工具条直接切换。
    mini_skin: String,
    /// 迷你窗工具条上的声音开关；与主窗口设置项共享同一份状态。
    woodfish_sound_enabled: bool,
    micro_break_enabled: bool,
    micro_break_interval_minutes: u64,
    /// 喝水与起身合成同一个轮换池：对用户来说都是「该歇一下了」，
    /// 拆成两类只会把复杂度转嫁到设置页。
    micro_break_messages: Vec<String>,
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
        if self.notification_mode.is_none() {
            self.notification_mode = Some(if self.legacy_reminder {
                NotificationMode::Simple
            } else {
                NotificationMode::Off
            });
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

    fn notification_mode(&self) -> NotificationMode {
        self.notification_mode.unwrap_or(NotificationMode::Off)
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

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct NotificationMarker {
    model_version: u8,
    end_at_ms: i64,
    sent_milestones: Vec<u8>,
    sent_break_starts: Vec<i64>,
    sent_break_ends: Vec<i64>,
    sent_micro_breaks: Vec<u64>,
    micro_break_interval_minutes: u64,
    /// 健康提醒只累计当前连续工作段。午休把班次拆成多个 segment，进入下一个
    /// segment 时从零重新计时，而不是续上午休前未满的一轮。
    micro_break_segment_start_at_ms: Option<i64>,
    last_observed_ms: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NotificationMilestone {
    Half = 50,
    ThreeQuarters = 75,
    Ninety = 90,
    NinetyFive = 95,
    Complete = 100,
}

impl NotificationMilestone {
    const ALL: [Self; 5] = [
        Self::Half,
        Self::ThreeQuarters,
        Self::Ninety,
        Self::NinetyFive,
        Self::Complete,
    ];

    fn percent(self) -> u8 {
        self as u8
    }
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

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DesktopMenuLabels {
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
            show: "Show app".into(),
            mini: "Mini timer".into(),
            quit: "Quit".into(),
            file: "File".into(),
            edit: "Edit".into(),
            view: "View".into(),
            window: "Window".into(),
            help: "Help".into(),
            about: "About Off Work Countdown".into(),
            services: "Services".into(),
            hide_app: "Hide Off Work Countdown".into(),
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

    extern "C" {
        fn owc_native_mini_initialize();
        fn owc_native_mini_toggle();
        fn owc_native_mini_hide();
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
    app.store(STORE_PATH)
        .ok()
        .and_then(|store| store.get(COUNTDOWN_KEY))
        .and_then(|value| serde_json::from_value::<CountdownState>(value).ok())
        .unwrap_or_default()
        .migrate_legacy()
}

fn write_countdown_state(app: &AppHandle, state: &CountdownState) {
    let Ok(store) = app.store(STORE_PATH) else {
        return;
    };
    if let Ok(value) = serde_json::to_value(state) {
        store.set(COUNTDOWN_KEY, value);
        let _ = store.save();
    }
}

fn read_notification_marker(app: &AppHandle) -> NotificationMarker {
    app.store(STORE_PATH)
        .ok()
        .and_then(|store| store.get(NOTIFICATION_MARKER_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn write_notification_marker(app: &AppHandle, marker: &NotificationMarker) {
    let Ok(store) = app.store(STORE_PATH) else {
        return;
    };
    if let Ok(value) = serde_json::to_value(marker) {
        store.set(NOTIFICATION_MARKER_KEY, value);
        let _ = store.save();
    }
}

/// 推进一次里程碑状态。无论通知档位是否开启，越过的节点都会标记为已处理，
/// 防止之后打开开关时补发；休眠一次跨过多个节点时只返回最高的一个。
fn advance_notification_marker(
    state: &CountdownState,
    marker: &mut NotificationMarker,
    now_ms: i64,
) -> (Option<NotificationMilestone>, bool) {
    if !state.running || !state.is_valid_shift() {
        return (None, false);
    }

    let end_at_ms = state.end_at_ms();
    let progress = (countdown_progress(state, now_ms) * 100.0).floor() as u8;
    let crossed: Vec<u8> = NotificationMilestone::ALL
        .iter()
        .map(|milestone| milestone.percent())
        .filter(|percent| *percent <= progress)
        .collect();

    if marker.model_version != 3 || marker.end_at_ms != end_at_ms {
        let sent_break_starts = state
            .segments
            .windows(2)
            .map(|pair| pair[0].end_at_ms)
            .filter(|boundary| *boundary <= now_ms)
            .collect();
        let sent_break_ends = state
            .segments
            .windows(2)
            .map(|pair| pair[1].start_at_ms)
            .filter(|boundary| *boundary <= now_ms)
            .collect();
        *marker = NotificationMarker {
            model_version: 3,
            end_at_ms,
            // 第一次看到班次时，把已经越过的节点视为已处理，不补发历史通知。
            sent_milestones: crossed,
            sent_break_starts,
            sent_break_ends,
            sent_micro_breaks: Vec::new(),
            micro_break_interval_minutes: state.micro_break_interval_minutes,
            micro_break_segment_start_at_ms: None,
            last_observed_ms: now_ms,
        };
        return (None, true);
    }

    let newly_crossed: Vec<u8> = crossed
        .into_iter()
        .filter(|percent| !marker.sent_milestones.contains(percent))
        .collect();
    if newly_crossed.is_empty() {
        return (None, false);
    }

    marker.sent_milestones.extend(newly_crossed.iter().copied());
    marker.sent_milestones.sort_unstable();
    marker.sent_milestones.dedup();

    let highest = *newly_crossed.last().expect("non-empty milestones");
    let notification = match state.notification_mode() {
        NotificationMode::Off => None,
        NotificationMode::Simple => (highest == 100).then_some(NotificationMilestone::Complete),
        NotificationMode::Milestones => NotificationMilestone::ALL
            .into_iter()
            .find(|milestone| milestone.percent() == highest),
    };

    (notification, true)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum BreakNotification {
    Start,
    End,
}

/// 午休边界只在仍处于对应阶段、且距边界不超过两分钟时通知。
/// 因而电脑睡眠跨过午休不会在唤醒后补发已经失去语境的提示。
fn advance_break_notification(
    state: &CountdownState,
    marker: &mut NotificationMarker,
    previous: i64,
    now_ms: i64,
) -> (Option<BreakNotification>, bool) {
    if !state.running || !state.is_valid_shift() || marker.end_at_ms != state.end_at_ms() {
        return (None, false);
    }
    let mut changed = false;
    const FRESH_MS: i64 = 2 * 60 * 1000;

    for pair in state.segments.windows(2) {
        let break_start = pair[0].end_at_ms;
        let break_end = pair[1].start_at_ms;
        if previous < break_start
            && now_ms >= break_start
            && now_ms < break_end
            && now_ms - break_start <= FRESH_MS
            && !marker.sent_break_starts.contains(&break_start)
        {
            marker.sent_break_starts.push(break_start);
            changed = true;
            return (
                state
                    .lunch_notification_enabled
                    .then_some(BreakNotification::Start),
                changed,
            );
        }
        if previous < break_end
            && now_ms >= break_end
            && now_ms < pair[1].end_at_ms
            && now_ms - break_end <= FRESH_MS
            && !marker.sent_break_ends.contains(&break_end)
        {
            marker.sent_break_ends.push(break_end);
            changed = true;
            return (
                state
                    .lunch_end_notification_enabled
                    .then_some(BreakNotification::End),
                changed,
            );
        }
    }
    (None, changed)
}

fn micro_break_body(state: &CountdownState, bucket: u64) -> Option<String> {
    let pool = &state.micro_break_messages;
    if pool.is_empty() {
        return None;
    }
    let template = pool.get(bucket as usize % pool.len())?;
    Some(template.replace(
        "{{minutes}}",
        &(bucket * state.micro_break_interval_minutes).to_string(),
    ))
}

fn advance_micro_break_marker(
    state: &CountdownState,
    marker: &mut NotificationMarker,
    previous: i64,
    now_ms: i64,
) -> (Option<String>, bool) {
    let interval_ms = state.micro_break_interval_minutes as i64 * 60 * 1000;
    if !state.running || !state.is_valid_shift() || interval_ms <= 0 {
        return (None, false);
    }

    let active_segment = state
        .segments
        .iter()
        .find(|segment| now_ms >= segment.start_at_ms && now_ms < segment.end_at_ms);

    // 午休期间没有活跃工作段：清掉上一段的周期。午休结束进入新的 segment
    // 时会重新建立基线，因此午休前没满的一轮不会被带到午休后。
    let Some(active_segment) = active_segment else {
        if marker.micro_break_segment_start_at_ms.is_none() && marker.sent_micro_breaks.is_empty() {
            return (None, false);
        }
        marker.micro_break_segment_start_at_ms = None;
        marker.sent_micro_breaks.clear();
        return (None, true);
    };

    let current_bucket = ((now_ms - active_segment.start_at_ms) / interval_ms).max(0) as u64;
    if marker.micro_break_segment_start_at_ms != Some(active_segment.start_at_ms) {
        marker.micro_break_segment_start_at_ms = Some(active_segment.start_at_ms);
        // 首次观察到这一连续工作段时不补发此前越过的健康提醒。
        marker.sent_micro_breaks = (1..=current_bucket).collect();
        return (None, true);
    }
    if marker.micro_break_interval_minutes != state.micro_break_interval_minutes {
        marker.micro_break_interval_minutes = state.micro_break_interval_minutes;
        marker.sent_micro_breaks = (1..=current_bucket).collect();
        // 修改间隔只重建去重基线，不立即弹一条“补发”提醒。
        return (None, true);
    }
    let last_bucket = ((previous - active_segment.start_at_ms).max(0) / interval_ms) as u64;
    if current_bucket == 0 || current_bucket <= last_bucket {
        return (None, false);
    }
    let crossed: Vec<u64> = ((last_bucket + 1)..=current_bucket).collect();
    let newest = *crossed.last().expect("non-empty micro-break range");
    marker.sent_micro_breaks.extend(crossed);
    marker.sent_micro_breaks.sort_unstable();
    marker.sent_micro_breaks.dedup();

    let fresh = now_ms.saturating_sub(previous) <= 2 * 60 * 1000;
    let body = (state.micro_break_enabled && fresh)
        .then(|| micro_break_body(state, newest))
        .flatten();
    (body, true)
}

fn notification_body(state: &CountdownState, milestone: NotificationMilestone) -> &str {
    let messages = match milestone {
        NotificationMilestone::Half => &state.notification_messages.milestone50,
        NotificationMilestone::ThreeQuarters => &state.notification_messages.milestone75,
        NotificationMilestone::Ninety => &state.notification_messages.milestone90,
        NotificationMilestone::NinetyFive => &state.notification_messages.milestone95,
        NotificationMilestone::Complete => &state.notification_messages.milestone100,
    };
    let fallback = match milestone {
        NotificationMilestone::Half => "Halfway there.",
        NotificationMilestone::ThreeQuarters => "The hardest part is behind you.",
        NotificationMilestone::Ninety => "Almost there.",
        NotificationMilestone::NinetyFive => "Just a little longer.",
        NotificationMilestone::Complete => "Off work time!",
    };
    let body = if messages.is_empty() {
        fallback
    } else {
        let seed = state.end_at_ms().unsigned_abs() as usize + milestone.percent() as usize;
        messages[seed % messages.len()].as_str()
    };
    body
}

#[cfg(desktop)]
fn send_countdown_notification(
    app: &AppHandle,
    state: &CountdownState,
    milestone: NotificationMilestone,
) {
    let title = if state.notification_title.is_empty() {
        "Off work reminder"
    } else {
        &state.notification_title
    };
    let body = notification_body(state, milestone);

    if let Err(error) = app.notification().builder().title(title).body(body).show() {
        log::warn!("failed to send countdown notification: {error}");
    }
}

#[cfg(desktop)]
fn send_break_notification(app: &AppHandle, state: &CountdownState, kind: BreakNotification) {
    let title = if state.notification_title.is_empty() {
        "Off work reminder"
    } else {
        &state.notification_title
    };
    let body = match kind {
        BreakNotification::Start => &state.lunch_start_notification,
        BreakNotification::End => &state.lunch_end_notification,
    };
    if !body.is_empty() {
        if let Err(error) = app.notification().builder().title(title).body(body).show() {
            log::warn!("failed to send break notification: {error}");
        }
    }
}

#[cfg(desktop)]
fn send_micro_break_notification(app: &AppHandle, state: &CountdownState, body: &str) {
    let title = if state.notification_title.is_empty() {
        "Off work reminder"
    } else {
        &state.notification_title
    };
    if let Err(error) = app.notification().builder().title(title).body(body).show() {
        log::warn!("failed to send micro-break notification: {error}");
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

fn format_remaining(remaining_ms: i64) -> String {
    let total_seconds = (remaining_ms.max(0) + 999) / 1000;
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
        let mut marker = read_notification_marker(&app);
        loop {
            let now_ms = chrono_free_now_ms();
            let mut state = read_countdown_state(&app);
            if advance_to_next_shift(&mut state, now_ms) {
                write_countdown_state(&app, &state);
            }
            let metrics = countdown_metrics(&state, now_ms);
            let active = metrics.is_some() && state.end_at_ms() > now_ms;
            // 午休时托盘显示距午休结束的时间，而不是冻住的下班倒计时——
            // 后者在整个午休期间纹丝不动，看起来像应用卡死了。
            let break_remaining = active
                .then(|| active_break_end_at_ms(&state, now_ms))
                .flatten()
                .map(|end| format_remaining(end - now_ms));
            let remaining = break_remaining
                .clone()
                .or_else(|| active.then(|| format_remaining(metrics.expect("active metrics").0)));
            let next_remaining = (!active && state.running)
                .then_some(state.next_shift.as_ref())
                .flatten()
                .filter(|next| next.is_valid() && next.segments[0].start_at_ms > now_ms)
                .map(|next| format_remaining(next.segments[0].start_at_ms - now_ms));

            let (notification, marker_changed) =
                advance_notification_marker(&state, &mut marker, now_ms);
            let previous_observed = marker.last_observed_ms;
            let (break_notification, break_marker_changed) =
                advance_break_notification(&state, &mut marker, previous_observed, now_ms);
            let (micro_break_notification, micro_break_marker_changed) =
                advance_micro_break_marker(&state, &mut marker, previous_observed, now_ms);
            marker.last_observed_ms = now_ms;
            if marker_changed || break_marker_changed || micro_break_marker_changed {
                write_notification_marker(&app, &marker);
            }
            if let Some(notification) = notification {
                send_countdown_notification(&app, &state, notification);
            }
            if let Some(notification) = break_notification {
                send_break_notification(&app, &state, notification);
            }
            if let Some(body) = micro_break_notification {
                send_micro_break_notification(&app, &state, &body);
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
                    .map(|time| format!("Off Work Countdown · {time}"))
                    .unwrap_or_else(|| "Off Work Countdown".to_string());
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
            // Windows 在倒计时开始时自动露出迷你窗；结束后不再强制隐藏，
            // 已经打开的窗口会切换为“计时未开始”，由用户决定是否收起。
            if (cfg!(target_os = "windows") || windows_mini_dev_override())
                && active
                && !was_running
            {
                if let Some(window) = app.get_webview_window("mini") {
                    let _ = window.show();
                }
            }

            #[cfg(any(target_os = "windows", debug_assertions))]
            {
                was_running = active;
            }
            thread::sleep(Duration::from_secs(1));
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

fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let menu = build_tray_menu(app, &DesktopMenuLabels::default())?;

    let icon = app
        .default_window_icon()
        .expect("bundle icon missing")
        .clone();

    TrayIconBuilder::with_id("main")
        .icon(icon)
        .tooltip("Off Work Countdown")
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
        })
        .build(app)?;

    Ok(())
}

/// 用前端当前语言重建 macOS 菜单栏。PredefinedMenuItem 保留系统快捷键和原生
/// selector，只替换可见文案；应用名按 D2 始终保持英文产品名。
#[cfg(target_os = "macos")]
fn set_macos_application_menu(app: &AppHandle, labels: &DesktopMenuLabels) -> tauri::Result<()> {
    let package = app.package_info();
    let about_metadata = AboutMetadata {
        name: Some(package.name.clone()),
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
        package.name.clone(),
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
    let store = app
        .store(STORE_PATH)
        .map_err(|error| std::io::Error::other(error.to_string()))?;
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
    let window = WebviewWindowBuilder::new(app, "mini", WebviewUrl::App(url.into()))
        .title("Off Work Countdown")
        // 四周各留 6pt 给圆角之外的投影。高度比旧版增加 6pt，让顶部工具栏
        // 与中间读数保持清晰间距；宽度仍与原来的紧凑挂件一致。
        .inner_size(240.0, 90.0)
        .min_inner_size(240.0, 90.0)
        .max_inner_size(240.0, 90.0)
        .resizable(false)
        .maximizable(false)
        .fullscreen(false)
        .decorations(false)
        // 无边框窗口若不透明，CSS 圆角只会把窗口自己的底色露在四个角上，
        // 看起来就是个直角方块。透明之后圆角和投影才由页面说了算。
        .transparent(true)
        .shadow(false)
        .always_on_top(always_on_top)
        .skip_taskbar(true)
        .visible(false)
        .build()?;

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
            if let Ok(store) = app_handle.store(STORE_PATH) {
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
        _ => {}
    });

    Ok(())
}

#[tauri::command]
fn get_mini_window_settings(app: AppHandle) -> Result<MiniWindowSettings, String> {
    let always_on_top = app
        .store(STORE_PATH)
        .map_err(|error| error.to_string())?
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
        let store = app.store(STORE_PATH).map_err(|error| error.to_string())?;
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

/// 迷你窗（原生面板或 WebView 版）上的眼睛按钮统一走这里翻转 hide_earnings。
///
/// 写回 store 后，store 插件会广播 `store://change`；主窗口和迷你窗都通过
/// `subscribeToDesktopCountdown` 订阅它，因此两边会同时更新。
fn flip_hide_earnings(app: &AppHandle) {
    let mut state = read_countdown_state(app);
    state.hide_earnings = !state.hide_earnings;
    if let Ok(store) = app.store(STORE_PATH) {
        if let Ok(value) = serde_json::to_value(&state) {
            store.set(COUNTDOWN_KEY, value);
        }
    }
}

#[tauri::command]
fn toggle_salary_visibility(app: AppHandle) {
    flip_hide_earnings(&app);
}

/// 迷你窗工具条上的皮肤切换。
#[tauri::command]
fn toggle_mini_skin(app: AppHandle) -> Result<(), String> {
    let store = app.store(STORE_PATH).map_err(|error| error.to_string())?;
    let mut state = match store.get(COUNTDOWN_KEY) {
        Some(value) => serde_json::from_value::<CountdownState>(value)
            .map_err(|error| error.to_string())?
            .migrate_legacy(),
        None => CountdownState::default(),
    };
    state.mini_skin = if state.mini_skin == "woodfish" {
        "standard".into()
    } else {
        "woodfish".into()
    };
    let value = serde_json::to_value(&state).map_err(|error| error.to_string())?;
    store.set(COUNTDOWN_KEY, value);
    store.save().map_err(|error| error.to_string())
}

/// 迷你窗工具条上的声音开关。与眼睛按钮同理：由 Rust 改写 store，
/// 主窗口的设置项通过订阅收到同一份状态，两处不会各说各话。
#[tauri::command]
fn toggle_woodfish_sound(app: AppHandle) -> Result<(), String> {
    let store = app.store(STORE_PATH).map_err(|error| error.to_string())?;
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
    app.store(STORE_PATH)
        .ok()
        .and_then(|store| store.get(GLOBAL_SHORTCUT_SETTINGS_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn persist_global_shortcut_settings(
    app: &AppHandle,
    settings: &GlobalShortcutSettings,
) -> Result<(), String> {
    let store = app.store(STORE_PATH).map_err(|error| error.to_string())?;
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
const MIRROR_UPDATER_ENDPOINT: &str = "https://gh-proxy.com/https://github.com/ififi2017/Off-Work-Countdown/releases/latest/download/latest-cn.json";

/// 通过镜像清单重新检查、下载并安装更新。
///
/// 没法复用前端的 updater 插件调用：JS 侧的 `check()` 只有 `proxy`（HTTP 代理）
/// 参数，而 gh-proxy 是 URL 前缀重写，两者不是一回事；而且安装包的真实地址
/// 来自清单内部，光把清单换掉不够——必须整条链路都走镜像，这只有 Rust 侧的
/// `UpdaterBuilder::endpoints()` 能在运行时做到。
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
        let _ = tray.set_tooltip(Some("Off Work Countdown"));
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build());

    // 单实例必须最先注册：它要在任何窗口创建之前拦下第二个进程，
    // 否则第二次启动会先建好窗口再被关掉，用户能看到窗口一闪。
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            focus_main_window(app);
        }));
        builder = builder
            .plugin(tauri_plugin_notification::init())
            .plugin(tauri_plugin_autostart::init(
                tauri_plugin_autostart::MacosLauncher::LaunchAgent,
                None,
            ))
            .plugin(
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
            toggle_salary_visibility,
            toggle_woodfish_sound,
            toggle_mini_skin,
            get_global_shortcut_settings,
            update_global_shortcut_settings,
            install_update_via_mirror,
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
            let _ = app
                .store(STORE_PATH)
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

            // 关闭主窗口时隐藏而非退出。真正的退出走托盘菜单里的 Quit。
            if let Some(window) = app.get_webview_window("main") {
                let handle = window.clone();
                window.on_window_event(move |event| {
                    if let WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = handle.hide();
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
mod notification_tests {
    use super::*;

    fn state(mode: NotificationMode) -> CountdownState {
        CountdownState {
            segments: vec![ShiftSegment {
                start_at_ms: 0,
                end_at_ms: 1_000,
            }],
            planned_end_at_ms: 1_000,
            running: true,
            notification_mode: Some(mode),
            ..Default::default()
        }
    }

    #[test]
    fn milestone_nodes_fire_once_in_order() {
        let countdown = state(NotificationMode::Milestones);
        let mut marker = NotificationMarker::default();

        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 0).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 500).0,
            Some(NotificationMilestone::Half)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 500).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 750).0,
            Some(NotificationMilestone::ThreeQuarters)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 900).0,
            Some(NotificationMilestone::Ninety)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 950).0,
            Some(NotificationMilestone::NinetyFive)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 1_000).0,
            Some(NotificationMilestone::Complete)
        );
    }

    #[test]
    fn simple_mode_only_notifies_at_completion() {
        let countdown = state(NotificationMode::Simple);
        let mut marker = NotificationMarker::default();
        advance_notification_marker(&countdown, &mut marker, 0);
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 950).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 1_000).0,
            Some(NotificationMilestone::Complete)
        );
    }

    #[test]
    fn wakeups_emit_only_the_highest_new_milestone() {
        let countdown = state(NotificationMode::Milestones);
        let mut marker = NotificationMarker::default();
        advance_notification_marker(&countdown, &mut marker, 400);
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 960).0,
            Some(NotificationMilestone::NinetyFive)
        );
        assert_eq!(marker.sent_milestones, vec![50, 75, 90, 95]);
    }

    #[test]
    fn disabled_or_stale_states_never_backfill() {
        let mut countdown = state(NotificationMode::Off);
        let mut marker = NotificationMarker::default();
        advance_notification_marker(&countdown, &mut marker, 0);
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 800).0,
            None
        );

        countdown.notification_mode = Some(NotificationMode::Milestones);
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 800).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 900).0,
            Some(NotificationMilestone::Ninety)
        );

        let mut stale_marker = NotificationMarker::default();
        assert_eq!(
            advance_notification_marker(&countdown, &mut stale_marker, 1_001).0,
            None
        );
        assert_eq!(stale_marker.sent_milestones, vec![50, 75, 90, 95, 100]);
    }

    #[test]
    fn notification_body_never_reads_salary_state() {
        let mut countdown = state(NotificationMode::Milestones);
        countdown.daily_salary = Some(123_456.78);
        countdown.notification_messages.milestone50 = vec!["Safe progress copy".into()];
        assert_eq!(
            notification_body(&countdown, NotificationMilestone::Half),
            "Safe progress copy"
        );
    }

    #[test]
    fn lunch_boundaries_notify_once_but_sleep_does_not_backfill() {
        let mut countdown = CountdownState {
            segments: vec![
                ShiftSegment {
                    start_at_ms: 0,
                    end_at_ms: 3_000,
                },
                ShiftSegment {
                    start_at_ms: 4_000,
                    end_at_ms: 10_000,
                },
            ],
            planned_end_at_ms: 10_000,
            running: true,
            lunch_notification_enabled: true,
            lunch_end_notification_enabled: true,
            ..Default::default()
        };
        let mut marker = NotificationMarker::default();
        advance_notification_marker(&countdown, &mut marker, 2_900);
        assert_eq!(
            advance_break_notification(&countdown, &mut marker, 2_900, 3_001).0,
            Some(BreakNotification::Start)
        );
        assert_eq!(
            advance_break_notification(&countdown, &mut marker, 3_001, 3_500).0,
            None
        );
        assert_eq!(
            advance_break_notification(&countdown, &mut marker, 3_500, 4_001).0,
            Some(BreakNotification::End)
        );

        // 新班次首次在午休后才被观察到，两个边界都视为历史，不补发。
        countdown.planned_end_at_ms = 20_000;
        countdown.segments = vec![
            ShiftSegment {
                start_at_ms: 10_000,
                end_at_ms: 13_000,
            },
            ShiftSegment {
                start_at_ms: 14_000,
                end_at_ms: 20_000,
            },
        ];
        advance_notification_marker(&countdown, &mut marker, 15_000);
        assert_eq!(
            advance_break_notification(&countdown, &mut marker, 15_000, 15_001).0,
            None
        );
    }

    #[test]
    fn switches_only_to_a_live_frontend_supplied_next_shift() {
        let mut countdown = state(NotificationMode::Off);
        countdown.next_shift = Some(ShiftTimelineState {
            segments: vec![ShiftSegment {
                start_at_ms: 2_000,
                end_at_ms: 3_000,
            }],
            planned_end_at_ms: 3_000,
            overtime_end_at_ms: None,
        });
        assert!(!advance_to_next_shift(&mut countdown, 1_500));
        assert!(advance_to_next_shift(&mut countdown, 2_100));
        assert_eq!(countdown.segments[0].start_at_ms, 2_000);
        assert!(countdown.next_shift.is_none());

        let mut stale = state(NotificationMode::Off);
        stale.next_shift = Some(ShiftTimelineState {
            segments: vec![ShiftSegment {
                start_at_ms: 2_000,
                end_at_ms: 3_000,
            }],
            planned_end_at_ms: 3_000,
            overtime_end_at_ms: None,
        });
        assert!(advance_to_next_shift(&mut stale, 4_000));
        assert!(!stale.running);
    }

    #[test]
    fn overtime_salary_uses_the_planned_hourly_rate() {
        let countdown = CountdownState {
            segments: vec![ShiftSegment {
                start_at_ms: 0,
                end_at_ms: 12_000,
            }],
            planned_end_at_ms: 10_000,
            overtime_end_at_ms: Some(12_000),
            running: true,
            ..Default::default()
        };
        assert!((countdown_pay_ratio(&countdown, 12_000) - 1.2).abs() < f64::EPSILON);
    }

    #[test]
    fn micro_breaks_pause_for_lunch_and_restart_after_it() {
        let countdown = CountdownState {
            segments: vec![
                ShiftSegment {
                    start_at_ms: 0,
                    end_at_ms: 50_000,
                },
                ShiftSegment {
                    start_at_ms: 90_000,
                    end_at_ms: 180_000,
                },
            ],
            planned_end_at_ms: 180_000,
            running: true,
            micro_break_enabled: true,
            micro_break_interval_minutes: 1,
            micro_break_messages: vec!["Worked {{minutes}} minutes; drink water.".into()],
            ..Default::default()
        };
        let mut marker = NotificationMarker {
            model_version: 3,
            end_at_ms: 180_000,
            last_observed_ms: 49_000,
            micro_break_interval_minutes: 1,
            micro_break_segment_start_at_ms: Some(0),
            ..Default::default()
        };

        // 午休期间不发送，并清掉午休前已经累计的 50 秒。
        assert_eq!(
            advance_micro_break_marker(&countdown, &mut marker, 49_000, 60_000),
            (None, true)
        );
        assert_eq!(marker.micro_break_segment_start_at_ms, None);
        assert_eq!(
            advance_micro_break_marker(&countdown, &mut marker, 60_000, 89_999),
            (None, false)
        );

        // 午休结束时建立新周期，但不会把上午的 50 秒接到下午。
        assert_eq!(
            advance_micro_break_marker(&countdown, &mut marker, 89_999, 90_000),
            (None, true)
        );
        assert_eq!(marker.micro_break_segment_start_at_ms, Some(90_000));
        assert_eq!(
            advance_micro_break_marker(&countdown, &mut marker, 90_000, 140_000),
            (None, false)
        );
        assert_eq!(
            advance_micro_break_marker(&countdown, &mut marker, 149_999, 150_000).0,
            Some("Worked 1 minutes; drink water.".into())
        );

        let mut changed = countdown.clone();
        changed.micro_break_interval_minutes = 2;
        assert_eq!(
            advance_micro_break_marker(&changed, &mut marker, 150_000, 150_001).0,
            None
        );
        assert_eq!(marker.micro_break_interval_minutes, 2);
    }
}

#[cfg(test)]
mod format_tests {
    use super::{
        countdown_metrics, countdown_progress, format_remaining, parse_global_shortcut,
        CountdownState, GlobalShortcutSettings, ShiftSegment, DEFAULT_GLOBAL_SHORTCUT,
    };

    #[test]
    fn formats_remaining_time_without_business_logic() {
        assert_eq!(format_remaining(3_661_000), "1:01:01");
        assert_eq!(format_remaining(-1), "0:00:00");
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
    fn global_shortcuts_require_a_modifier_and_keep_the_legacy_default() {
        let settings = GlobalShortcutSettings::default();
        assert!(settings.enabled);
        assert_eq!(settings.accelerator, DEFAULT_GLOBAL_SHORTCUT);
        assert!(parse_global_shortcut("Shift+KeyK").is_ok());
        assert!(parse_global_shortcut("KeyK").is_err());
        assert!(parse_global_shortcut("Shift").is_err());
    }
}
