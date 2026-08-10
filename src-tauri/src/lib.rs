use serde::{Deserialize, Serialize};
#[cfg(target_os = "macos")]
use std::sync::OnceLock;
use std::{thread, time::Duration};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
#[cfg(any(target_os = "windows", debug_assertions))]
use tauri::{PhysicalPosition, WebviewUrl, WebviewWindowBuilder};
#[cfg(desktop)]
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
#[cfg(desktop)]
use tauri_plugin_notification::NotificationExt;
#[cfg(any(target_os = "windows", debug_assertions))]
use tauri_plugin_positioner::{Position, WindowExt};
use tauri_plugin_store::StoreExt;

const STORE_PATH: &str = "desktop-state.json";
const COUNTDOWN_KEY: &str = "countdown";
const NOTIFICATION_MARKER_KEY: &str = "notificationMarker";
const REMINDER_LEAD_MS: i64 = 15 * 60 * 1000;
#[cfg(any(target_os = "windows", debug_assertions))]
const MINI_POSITION_KEY: &str = "miniPosition";
const MINI_ALWAYS_ON_TOP_KEY: &str = "miniAlwaysOnTop";

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

/// 是否启用 WebView 版迷你窗。macOS 正常情况下走原生面板，不建这个窗口。
///
/// 门控条件与它的所有调用点一致：macOS release 构建里这些代码都不存在，
/// 函数本身也就不必编译。
#[cfg(any(target_os = "windows", debug_assertions))]
fn mini_window_enabled() -> bool {
    cfg!(target_os = "windows") || windows_mini_dev_override()
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct CountdownState {
    start_at_ms: i64,
    end_at_ms: i64,
    running: bool,
    reminder: bool,
    lead_reminder_armed: bool,
    notification_title: String,
    lead_notification_body: String,
    completion_notification_body: String,
    show_salary: bool,
    hide_earnings: bool,
    daily_salary: Option<f64>,
    lang: String,
    countdown_not_started: String,
    /// 眼睛按钮的无障碍描述。面板其余文案都随界面语言走，这两个如果留在
    /// ObjC 里硬编码英文，VoiceOver 用户会在一堆中文里听到 "Hide salary"。
    show_earnings_label: String,
    hide_earnings_label: String,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
#[serde(rename_all = "camelCase")]
struct NotificationMarker {
    end_at_ms: i64,
    lead_sent: bool,
    completion_sent: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CountdownNotification {
    Lead,
    Complete,
}

#[cfg(any(target_os = "windows", debug_assertions))]
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

struct TrayMenuItems {
    show: MenuItem<tauri::Wry>,
    mini: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
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

fn hide_mini_window(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    if !windows_mini_dev_override() {
        native_mini::hide();
        return;
    }

    #[cfg(any(target_os = "windows", debug_assertions))]
    if let Some(window) = app.get_webview_window("mini") {
        let _ = window.hide();
    }

    let _ = app;
}

fn read_countdown_state(app: &AppHandle) -> CountdownState {
    app.store(STORE_PATH)
        .ok()
        .and_then(|store| store.get(COUNTDOWN_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn read_notification_marker(app: &AppHandle) -> NotificationMarker {
    app.store(STORE_PATH)
        .ok()
        .and_then(|store| store.get(NOTIFICATION_MARKER_KEY))
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn write_notification_marker(app: &AppHandle, marker: NotificationMarker) {
    let Ok(store) = app.store(STORE_PATH) else {
        return;
    };
    if let Ok(value) = serde_json::to_value(marker) {
        store.set(NOTIFICATION_MARKER_KEY, value);
        let _ = store.save();
    }
}

/// 推进一次提醒状态。返回值只表示本次需要发送的类型；无论提醒开关是否打开，
/// 越过的节点都会标记为已处理，防止之后打开开关时补发一条过期通知。
fn advance_notification_marker(
    state: &CountdownState,
    marker: &mut NotificationMarker,
    now_ms: i64,
) -> (Option<CountdownNotification>, bool) {
    if !state.running || state.end_at_ms <= state.start_at_ms {
        return (None, false);
    }

    let mut changed = false;
    if marker.end_at_ms != state.end_at_ms {
        *marker = NotificationMarker {
            end_at_ms: state.end_at_ms,
            lead_sent: !state.lead_reminder_armed,
            // 第一次观察到的就是已结束快照时视为旧状态，不在启动时补发。
            completion_sent: now_ms >= state.end_at_ms,
        };
        changed = true;
    }

    let notification = if now_ms >= state.end_at_ms && !marker.completion_sent {
        marker.completion_sent = true;
        changed = true;
        state.reminder.then_some(CountdownNotification::Complete)
    } else if now_ms >= state.end_at_ms - REMINDER_LEAD_MS
        && now_ms < state.end_at_ms
        && !marker.lead_sent
    {
        marker.lead_sent = true;
        changed = true;
        state.reminder.then_some(CountdownNotification::Lead)
    } else {
        None
    };

    (notification, changed)
}

#[cfg(desktop)]
fn send_countdown_notification(
    app: &AppHandle,
    state: &CountdownState,
    notification: CountdownNotification,
) {
    let title = if state.notification_title.is_empty() {
        "Off work reminder"
    } else {
        &state.notification_title
    };
    let body = match notification {
        CountdownNotification::Lead if !state.lead_notification_body.is_empty() => {
            &state.lead_notification_body
        }
        CountdownNotification::Complete if !state.completion_notification_body.is_empty() => {
            &state.completion_notification_body
        }
        CountdownNotification::Lead => "Fifteen minutes left!",
        CountdownNotification::Complete => "Off work time!",
    };

    if let Err(error) = app.notification().builder().title(title).body(body).show() {
        log::warn!("failed to send countdown notification: {error}");
    }
}

fn format_remaining(end_at_ms: i64, now_ms: i64) -> String {
    let total_seconds = ((end_at_ms - now_ms).max(0) + 999) / 1000;
    let hours = total_seconds / 3600;
    let minutes = (total_seconds % 3600) / 60;
    let seconds = total_seconds % 60;
    format!("{hours}:{minutes:02}:{seconds:02}")
}

/// 非 macOS 构建里只有单元测试会调用它（原生面板是 macOS 独有的）。
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn countdown_progress(state: &CountdownState, now_ms: i64) -> f64 {
    if !state.running || state.end_at_ms <= state.start_at_ms {
        return 0.0;
    }
    let duration = (state.end_at_ms - state.start_at_ms) as f64;
    ((now_ms - state.start_at_ms) as f64 / duration).clamp(0.0, 1.0)
}

/// 独立于 WebView 的后台节拍器。这里只做绝对时间戳相减；跨夜班次等业务
/// 规则仍由前端唯一实现。即便主窗口隐藏，托盘与迷你窗生命周期也不受影响。
fn start_tray_timer(app: AppHandle) {
    thread::spawn(move || {
        #[cfg(any(target_os = "windows", debug_assertions))]
        let mut was_running = false;
        loop {
            let state = read_countdown_state(&app);
            let now_ms = chrono_free_now_ms();
            let valid = state.running && state.end_at_ms > state.start_at_ms;
            let active = valid && state.end_at_ms > now_ms;
            let remaining = active.then(|| format_remaining(state.end_at_ms, now_ms));

            let mut marker = read_notification_marker(&app);
            let (notification, marker_changed) =
                advance_notification_marker(&state, &mut marker, now_ms);
            if marker_changed {
                write_notification_marker(&app, marker);
            }
            if let Some(notification) = notification {
                send_countdown_notification(&app, &state, notification);
            }

            if let Some(tray) = app.tray_by_id("main") {
                #[cfg(target_os = "macos")]
                let _ = tray.set_title(Some(remaining.as_deref().unwrap_or("")));

                let tooltip = remaining
                    .as_deref()
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
                        .map(|salary| format!("{:.2}", salary * progress))
                        .unwrap_or_default()
                } else {
                    String::new()
                };
                let empty_text = if state.countdown_not_started.is_empty() {
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
            if active && !was_running {
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
fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
    let mini = MenuItem::with_id(app, "mini", "Mini Timer", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &mini, &quit])?;

    app.manage(TrayMenuItems {
        show: show.clone(),
        mini: mini.clone(),
        quit: quit.clone(),
    });

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

#[cfg(any(target_os = "windows", debug_assertions))]
fn setup_mini_window(app: &AppHandle) -> tauri::Result<()> {
    let store = app
        .store(STORE_PATH)
        .map_err(|error| std::io::Error::other(error.to_string()))?;
    let always_on_top = store
        .get(MINI_ALWAYS_ON_TOP_KEY)
        .and_then(|value| value.as_bool())
        .unwrap_or(true);
    let url = if cfg!(debug_assertions) {
        "en/mini"
    } else {
        "en/mini.html"
    };
    let window = WebviewWindowBuilder::new(app, "mini", WebviewUrl::App(url.into()))
        .title("Off Work Countdown")
        // 内容面板与 macOS 原生面板同宽（228×72），四周各留 6pt 给圆角
        // 之外的投影，所以窗口本身要大一圈。
        .inner_size(240.0, 84.0)
        .min_inner_size(240.0, 84.0)
        .max_inner_size(240.0, 84.0)
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
        let _ = window.set_position(PhysicalPosition::new(position.x, position.y));
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
    #[cfg(any(target_os = "windows", debug_assertions))]
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
fn update_tray_menu(
    app: AppHandle,
    show_label: String,
    mini_label: String,
    quit_label: String,
) -> Result<(), String> {
    let items = app.state::<TrayMenuItems>();
    items
        .show
        .set_text(show_label)
        .map_err(|error| error.to_string())?;
    items
        .mini
        .set_text(mini_label)
        .map_err(|error| error.to_string())?;
    items
        .quit
        .set_text(quit_label)
        .map_err(|error| error.to_string())?;
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
            hide_mini_timer,
            show_main_window,
            toggle_salary_visibility,
            install_update_via_mirror,
            update_tray_menu,
            clear_desktop_countdown_display
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
            if let Err(error) = app.global_shortcut().register("CommandOrControl+Shift+O") {
                // 快捷键冲突不应阻止应用启动；用户仍可用 Dock/任务栏与托盘唤起。
                log::warn!("failed to register global shortcut: {error}");
            }
            setup_tray(app.handle())?;
            #[cfg(target_os = "macos")]
            {
                APP_HANDLE.set(app.handle().clone()).ok();
                native_mini::initialize();
                // 本地 UI 验收可显式要求启动时展示原生面板；正式包未设置该
                // 环境变量，因此仍只在用户点击托盘图标后出现。
                if cfg!(debug_assertions) && std::env::var_os("OWC_SHOW_NATIVE_MINI").is_some() {
                    native_mini::toggle();
                }
            }
            #[cfg(any(target_os = "windows", debug_assertions))]
            if mini_window_enabled() {
                setup_mini_window(app.handle())?;
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

    fn state(end_at_ms: i64) -> CountdownState {
        CountdownState {
            start_at_ms: 1_000,
            end_at_ms,
            running: true,
            reminder: true,
            lead_reminder_armed: true,
            ..Default::default()
        }
    }

    #[test]
    fn reminder_nodes_fire_once_in_order() {
        let countdown = state(2_000_000);
        let mut marker = NotificationMarker::default();

        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 1_099_999).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 1_100_000).0,
            Some(CountdownNotification::Lead)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 1_100_001).0,
            None
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 2_000_000).0,
            Some(CountdownNotification::Complete)
        );
        assert_eq!(
            advance_notification_marker(&countdown, &mut marker, 2_000_001).0,
            None
        );
    }

    #[test]
    fn short_or_stale_countdowns_do_not_backfill_notifications() {
        let mut short = state(2_000_000);
        short.lead_reminder_armed = false;
        let mut marker = NotificationMarker::default();
        assert_eq!(
            advance_notification_marker(&short, &mut marker, 1_500_000).0,
            None
        );

        let stale = state(2_000_000);
        let mut stale_marker = NotificationMarker::default();
        assert_eq!(
            advance_notification_marker(&stale, &mut stale_marker, 2_000_001).0,
            None
        );
    }
}

#[cfg(test)]
mod format_tests {
    use super::{countdown_progress, format_remaining, CountdownState};

    #[test]
    fn formats_remaining_time_without_business_logic() {
        assert_eq!(format_remaining(3_661_001, 1), "1:01:01");
        assert_eq!(format_remaining(1, 2), "0:00:00");
    }

    #[test]
    fn clamps_native_mini_progress_to_the_shift() {
        let state = CountdownState {
            start_at_ms: 1_000,
            end_at_ms: 2_000,
            running: true,
            ..Default::default()
        };
        assert_eq!(countdown_progress(&state, 500), 0.0);
        assert_eq!(countdown_progress(&state, 1_500), 0.5);
        assert_eq!(countdown_progress(&state, 2_500), 1.0);
        assert_eq!(countdown_progress(&CountdownState::default(), 1_500), 0.0);
    }
}
