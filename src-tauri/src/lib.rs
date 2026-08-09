use serde::{Deserialize, Serialize};
use std::{thread, time::Duration};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
#[cfg(target_os = "windows")]
use tauri::{window::Color, PhysicalPosition, WebviewUrl, WebviewWindowBuilder};
#[cfg(desktop)]
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
#[cfg(desktop)]
use tauri_plugin_notification::NotificationExt;
#[cfg(target_os = "windows")]
use tauri_plugin_positioner::{Position, WindowExt};
use tauri_plugin_store::StoreExt;

const STORE_PATH: &str = "desktop-state.json";
const COUNTDOWN_KEY: &str = "countdown";
const NOTIFICATION_MARKER_KEY: &str = "notificationMarker";
const REMINDER_LEAD_MS: i64 = 15 * 60 * 1000;
#[cfg(target_os = "windows")]
const MINI_POSITION_KEY: &str = "miniPosition";
const MINI_ALWAYS_ON_TOP_KEY: &str = "miniAlwaysOnTop";

#[derive(Clone, Debug, Default, Deserialize)]
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

#[cfg(target_os = "windows")]
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
            detail: *const c_char,
            progress: f64,
            running: i32,
            empty_text: *const c_char,
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

    pub fn update(time: &str, detail: &str, progress: f64, running: bool, empty_text: &str) {
        let time = c_string(time);
        let detail = c_string(detail);
        let empty_text = c_string(empty_text);
        unsafe {
            owc_native_mini_update(
                time.as_ptr(),
                detail.as_ptr(),
                progress,
                i32::from(running),
                empty_text.as_ptr(),
            )
        }
    }
}

fn platform_name() -> &'static str {
    #[cfg(target_os = "macos")]
    return "macos";
    #[cfg(target_os = "windows")]
    return "windows";
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    return "other";
}

/// 显示并聚焦主窗口。窗口可能处于隐藏（关闭到托盘）或最小化状态，
/// 三步都要做，只调 set_focus 对隐藏窗口无效。
fn show_main_window(app: &AppHandle) {
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
        show_main_window(app);
    }
}

fn toggle_mini_window(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    {
        let _ = app;
        native_mini::toggle();
    }

    #[cfg(target_os = "windows")]
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

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
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
        #[cfg(target_os = "windows")]
        let mut was_running = false;
        loop {
            let state = read_countdown_state(&app);
            let now_ms = chrono_free_now_ms();
            let valid = state.running && state.end_at_ms > state.start_at_ms;
            let active = valid && state.end_at_ms > now_ms;
            let remaining = active.then(|| format_remaining(state.end_at_ms, now_ms));
            let progress = countdown_progress(&state, now_ms);

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
                let detail = if active && state.show_salary && !state.hide_earnings {
                    state
                        .daily_salary
                        .filter(|salary| salary.is_finite())
                        .map(|salary| format!("{:.2}", salary * progress))
                        .unwrap_or_else(|| format!("{}%", (progress * 100.0).floor() as i64))
                } else if active {
                    format!("{}%", (progress * 100.0).floor() as i64)
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
                    &detail,
                    progress,
                    active,
                    empty_text,
                );
            }

            #[cfg(target_os = "windows")]
            // Windows 在倒计时开始时自动露出迷你窗；结束后不再强制隐藏，
            // 已经打开的窗口会切换为“计时未开始”，由用户决定是否收起。
            if active && !was_running {
                if let Some(window) = app.get_webview_window("mini") {
                    let _ = window.show();
                }
            }

            #[cfg(target_os = "windows")]
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
            "show" => show_main_window(app),
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

#[cfg(target_os = "windows")]
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
        .inner_size(208.0, 64.0)
        .min_inner_size(208.0, 64.0)
        .max_inner_size(208.0, 64.0)
        .resizable(false)
        .maximizable(false)
        .fullscreen(false)
        .decorations(false)
        .background_color(Color(236, 236, 238, 255))
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
    #[cfg(target_os = "windows")]
    {
        let window = app
            .get_webview_window("mini")
            .ok_or_else(|| "mini window is unavailable".to_string())?;
        window
            .set_always_on_top(always_on_top)
            .map_err(|error| error.to_string())?;
        let store = app.store(STORE_PATH).map_err(|error| error.to_string())?;
        store.set(MINI_ALWAYS_ON_TOP_KEY, always_on_top);
        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, always_on_top);
        Ok(())
    }
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
            show_main_window(app);
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
                native_mini::initialize();
                // 本地 UI 验收可显式要求启动时展示原生面板；正式包未设置该
                // 环境变量，因此仍只在用户点击托盘图标后出现。
                if cfg!(debug_assertions) && std::env::var_os("OWC_SHOW_NATIVE_MINI").is_some() {
                    native_mini::toggle();
                }
            }
            #[cfg(target_os = "windows")]
            setup_mini_window(app.handle())?;
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
                show_main_window(app);
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
