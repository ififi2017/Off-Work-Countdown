use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager, WindowEvent,
};

/// 显示并聚焦主窗口。窗口可能处于隐藏（关闭到托盘）或最小化状态，
/// 三步都要做，只调 set_focus 对隐藏窗口无效。
fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// 托盘图标与菜单。
///
/// P1 只做「显示 / 退出」两项，托盘上的实时倒计时属于 P2。
/// 菜单文案暂为英文：托盘标题按计划是语言无关的时间格式，但菜单项需要本地化，
/// 这需要 Rust 侧读取用户选择的语言，留到 P2 与托盘标题一并处理。
fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    let icon = app
        .default_window_icon()
        .expect("bundle icon missing")
        .clone();

    TrayIconBuilder::with_id("main")
        .icon(icon)
        .tooltip("Off Work Countdown")
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => show_main_window(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default();

    // 单实例必须最先注册：它要在任何窗口创建之前拦下第二个进程，
    // 否则第二次启动会先建好窗口再被关掉，用户能看到窗口一闪。
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            show_main_window(app);
        }));
    }

    builder
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            setup_tray(app.handle())?;

            // 关闭窗口时隐藏而非退出。这是桌面端存在的理由之一：倒计时与提醒
            // 应当在窗口关掉之后继续运行，而不是随窗口一起消失。
            // 真正的退出走托盘菜单里的 Quit。
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
            // 因此单实例插件不会触发。若此时窗口已被关闭到托盘，没有这个分支
            // 用户点 Dock 图标会毫无反应——窗口再也回不来。
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
