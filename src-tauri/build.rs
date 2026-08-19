#[cfg(target_os = "macos")]
fn build_native_mini_timer() {
    use std::{env, path::PathBuf, process::Command};

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let source = manifest_dir.join("native-mini/NativeMiniTimer.m");
    let widget_bridge_source = manifest_dir.join("macappstore/WidgetHostBridge.swift");
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let object = out_dir.join("NativeMiniTimer.o");
    let widget_bridge_object = out_dir.join("WidgetHostBridge.o");
    let library = out_dir.join("libNativeMiniTimer.a");
    let module_cache = out_dir.join("clang-module-cache");
    std::fs::create_dir_all(&module_cache).expect("failed to create Clang module cache");
    let rust_target = env::var("TARGET").unwrap();
    let architecture = if rust_target.starts_with("aarch64") {
        "arm64"
    } else if rust_target.starts_with("x86_64") {
        "x86_64"
    } else {
        panic!("unsupported macOS architecture for native Mini Timer: {rust_target}");
    };
    let sdk_output = Command::new("xcrun")
        .args(["--sdk", "macosx", "--show-sdk-path"])
        .output()
        .expect("failed to locate the macOS SDK");
    if !sdk_output.status.success() {
        panic!("xcrun could not locate the macOS SDK");
    }
    let sdk = String::from_utf8(sdk_output.stdout)
        .expect("macOS SDK path was not UTF-8")
        .trim()
        .to_string();

    // 原生代码的最低系统版本必须跟着渠道走，不能写死：GitHub 版是 11.3，商店版是
    // 13.0（登录项要 SMAppService、小组件要 WidgetKit）。Tauri CLI 会按各自配置里的
    // `bundle.macOS.minimumSystemVersion` 设置 MACOSX_DEPLOYMENT_TARGET，这里读它即可，
    // 两边自然对齐。
    //
    // ⚠️ 写死一个高于 Rust 侧的值会造出一个**对外声称能跑、实际跑不了**的包：曾经
    // 这里固定 13.0，而 tauri.conf.json 没设 minimumSystemVersion（Tauri 默认 10.13），
    // 于是 GitHub 版的 .app 声称支持 10.13、二进制却是 11.0。
    //
    // 裸 cargo（CI 的 Rust job、本地 clippy、rust-analyzer）不经过 Tauri CLI，没有这个
    // 环境变量，此时按正在构建的渠道回退：商店渠道必须是 13.0，低于它 swiftc 会为
    // WidgetHostBridge.swift 生成回溯部署的兼容库引用（swiftCompatibility56、
    // swiftCompatibilityConcurrency 等），而那些静态库不在链接行里，直接链接失败。
    let include_widget_bridge = env::var_os("CARGO_FEATURE_SELF_UPDATE").is_none();
    let deployment_target = env::var("MACOSX_DEPLOYMENT_TARGET").unwrap_or_else(|_| {
        if include_widget_bridge {
            "13.0"
        } else {
            "11.3"
        }
        .to_string()
    });

    let mut clang = Command::new("clang");
    clang
        .arg("-c")
        .arg(&source)
        .args(["-o", object.to_str().unwrap()])
        .args(["-arch", architecture])
        .arg(format!("-mmacosx-version-min={deployment_target}"))
        .args(["-isysroot", &sdk])
        .arg("-fobjc-arc")
        .arg("-fmodules")
        .arg(format!("-fmodules-cache-path={}", module_cache.display()));
    if env::var("PROFILE").as_deref() == Ok("release") {
        clang.arg("-O2");
    } else {
        clang.arg("-O0");
    }
    let output = clang.output().expect("failed to run clang");
    if !output.status.success() {
        panic!(
            "failed to compile native Mini Timer:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    if include_widget_bridge {
        // 取值必须与 scripts/build-macos-widget.sh 的同名变量保持一致：那边决定
        // entitlements 怎么生成，这边决定宿主往哪个容器写快照，两者对不上的表现
        // 是运行期写入失败而不是构建失败。拼错的值在这里就炸掉，别等到 cargo
        // 跑完之后再由 beforeBundleCommand 拦下。
        let widget_storage_mode = match env::var("OWC_WIDGET_SIGNING_MODE").as_deref() {
            Ok("automatic") => "app-group",
            // 未设置时与脚本的默认值 adhoc 对齐。
            Ok("adhoc") | Ok("none") | Err(_) => "local-support",
            Ok(other) => {
                panic!("OWC_WIDGET_SIGNING_MODE must be adhoc, automatic, or none (got {other})")
            }
        };
        println!("cargo:rustc-env=OWC_WIDGET_STORAGE_MODE={widget_storage_mode}");
        let swift_target = format!("{architecture}-apple-macosx{deployment_target}");
        let mut swiftc = Command::new("xcrun");
        swiftc
            .args(["--sdk", "macosx", "swiftc"])
            .arg("-parse-as-library")
            .arg("-emit-object")
            .arg(&widget_bridge_source)
            .args(["-target", &swift_target])
            .args(["-sdk", &sdk])
            .args(["-module-cache-path", module_cache.to_str().unwrap()])
            .args(["-o", widget_bridge_object.to_str().unwrap()]);
        if env::var("PROFILE").as_deref() == Ok("release") {
            swiftc.arg("-O");
        } else {
            swiftc.arg("-Onone");
        }
        let output = swiftc.output().expect("failed to run swiftc");
        if !output.status.success() {
            panic!(
                "failed to compile Widget host bridge:\n{}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    let mut ar = Command::new("ar");
    ar.args(["crus", library.to_str().unwrap(), object.to_str().unwrap()]);
    if include_widget_bridge {
        ar.arg(&widget_bridge_object);
    }
    let output = ar.output().expect("failed to archive native macOS bridge");
    if !output.status.success() {
        panic!(
            "failed to archive native Mini Timer:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    println!("cargo:rerun-if-changed={}", source.display());
    println!("cargo:rerun-if-changed={}", widget_bridge_source.display());
    println!("cargo:rerun-if-env-changed=OWC_APP_GROUP_IDENTIFIER");
    println!("cargo:rerun-if-env-changed=OWC_WIDGET_SIGNING_MODE");
    println!("cargo:rerun-if-env-changed=MACOSX_DEPLOYMENT_TARGET");
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=NativeMiniTimer");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=QuartzCore");
    println!("cargo:rustc-link-lib=framework=ServiceManagement");
    if include_widget_bridge {
        println!("cargo:rustc-link-search=native={sdk}/usr/lib/swift");
        println!("cargo:rustc-link-lib=dylib=swiftCore");
        // The bridge imports no business module; WidgetKit is used only to ask
        // the system to reload the timeline after the atomic App Group write.
        println!("cargo:rustc-link-lib=framework=WidgetKit");
        for library in [
            "swiftCoreFoundation",
            "swiftCoreImage",
            "swiftCoreLocation",
            "swiftDispatch",
            "swiftFoundation",
            "swiftIOKit",
            "swiftIntents",
            "swiftMetal",
            "swiftOSLog",
            "swiftObjectiveC",
            "swiftQuartzCore",
            "swiftSpatial",
            "swiftUniformTypeIdentifiers",
            "swiftXPC",
            "swift_Builtin_float",
            "swiftos",
            "swiftsimd",
        ] {
            println!("cargo:rustc-link-lib=dylib={library}");
        }
    }
}

fn main() {
    #[cfg(target_os = "macos")]
    build_native_mini_timer();
    tauri_build::build()
}
