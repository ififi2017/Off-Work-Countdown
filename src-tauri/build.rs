#[cfg(target_os = "macos")]
fn build_native_mini_timer() {
    use std::{env, path::PathBuf, process::Command};

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let source = manifest_dir.join("native-mini/NativeMiniTimer.m");
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let object = out_dir.join("NativeMiniTimer.o");
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

    let mut clang = Command::new("clang");
    clang
        .arg("-c")
        .arg(&source)
        .args(["-o", object.to_str().unwrap()])
        .args(["-arch", architecture])
        .arg("-mmacosx-version-min=13.0")
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

    let output = Command::new("ar")
        .args(["crus", library.to_str().unwrap(), object.to_str().unwrap()])
        .output()
        .expect("failed to archive native Mini Timer");
    if !output.status.success() {
        panic!(
            "failed to archive native Mini Timer:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    println!("cargo:rerun-if-changed={}", source.display());
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=NativeMiniTimer");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=QuartzCore");
}

fn main() {
    #[cfg(target_os = "macos")]
    build_native_mini_timer();
    tauri_build::build()
}
