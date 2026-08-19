#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
widget_root="$project_root/src-tauri/macos-widget"
derived_data="$project_root/src-tauri/target/macos-widget"
configuration=${OWC_WIDGET_CONFIGURATION:-Release}
app_group_identifier=${OWC_APP_GROUP_IDENTIFIER:-group.com.rainif.offworkcountdown.macappstore}
widget_bundle_identifier=${OWC_WIDGET_BUNDLE_IDENTIFIER:-com.rainif.offworkcountdown.macappstore.widget}
build_number=${OWC_WIDGET_BUILD_NUMBER:-1}
signing_mode=${OWC_WIDGET_SIGNING_MODE:-adhoc}
marketing_version=$(node -p "require('$project_root/package.json').version")

case "$signing_mode" in
  automatic) widget_storage_mode=app-group ;;
  adhoc|none) widget_storage_mode=local-support ;;
  *)
    echo "OWC_WIDGET_SIGNING_MODE must be adhoc, automatic, or none." >&2
    exit 1
    ;;
esac

case "$app_group_identifier" in
  *[!A-Za-z0-9.-]*|'')
    echo "Invalid OWC_APP_GROUP_IDENTIFIER: $app_group_identifier" >&2
    exit 1
    ;;
esac

case "$widget_bundle_identifier" in
  *[!A-Za-z0-9.-]*|'')
    echo "Invalid OWC_WIDGET_BUNDLE_IDENTIFIER: $widget_bundle_identifier" >&2
    exit 1
    ;;
esac

mkdir -p "$derived_data"
sed "s|__OWC_APP_GROUP_IDENTIFIER__|$app_group_identifier|g" \
  "$project_root/src-tauri/macappstore/Entitlements.plist" \
  > "$derived_data/Host.entitlements"
plutil -lint "$derived_data/Host.entitlements" >/dev/null

# App Groups require a real team signature/provisioning profile. An ad-hoc
# signature is rejected by containermanagerd and macOS 15+ shows an "other App
# data" prompt. Local packages therefore keep App Sandbox but remove App Group,
# then grant a narrow temporary exception to the salary-free snapshot directory.
# Automatic/App Store packages keep the production sandbox + App Group architecture.
if [ "$widget_storage_mode" = "local-support" ]; then
  plutil -remove 'com\.apple\.security\.application-groups' \
    "$derived_data/Host.entitlements"
  plutil -insert \
    'com\.apple\.security\.temporary-exception\.files\.home-relative-path\.read-write' \
    -json '["/Library/Application Support/com.rainif.offworkcountdown.macappstore.local-widget/"]' \
    "$derived_data/Host.entitlements"
fi

# The Widget reads only the shared snapshot and performs no networking.
cp "$derived_data/Host.entitlements" "$derived_data/Widget.entitlements"
plutil -remove 'com\.apple\.security\.network\.client' \
  "$derived_data/Widget.entitlements"
if [ "$widget_storage_mode" = "local-support" ]; then
  plutil -remove \
    'com\.apple\.security\.temporary-exception\.files\.home-relative-path\.read-write' \
    "$derived_data/Widget.entitlements"
  plutil -insert \
    'com\.apple\.security\.temporary-exception\.files\.home-relative-path\.read-only' \
    -json '["/Library/Application Support/com.rainif.offworkcountdown.macappstore.local-widget/"]' \
    "$derived_data/Widget.entitlements"
fi
plutil -lint "$derived_data/Widget.entitlements" >/dev/null

set -- xcodebuild \
  -quiet \
  -project "$widget_root/OffWorkCountdownWidget.xcodeproj" \
  -scheme OffWorkCountdownWidgetExtension \
  -configuration "$configuration" \
  -sdk macosx \
  -destination generic/platform=macOS \
  -derivedDataPath "$derived_data" \
  CLANG_MODULE_CACHE_PATH=/private/tmp/off-work-countdown-xcode-module-cache \
  "MARKETING_VERSION=$marketing_version" \
  "CURRENT_PROJECT_VERSION=$build_number" \
  "OWC_APP_GROUP_IDENTIFIER=$app_group_identifier" \
  "OWC_WIDGET_STORAGE_MODE=$widget_storage_mode" \
  "PRODUCT_BUNDLE_IDENTIFIER=$widget_bundle_identifier"

case "$signing_mode" in
  automatic)
    if [ -z "${OWC_APPLE_TEAM_ID:-}" ]; then
      echo "OWC_APPLE_TEAM_ID is required for automatic Widget signing." >&2
      exit 1
    fi
    # -allowProvisioningUpdates：没有它 xcodebuild 只会去找**已存在**的描述文件，
    # 找不到就直接失败（"Automatic signing is disabled and unable to generate a
    # profile"）。加上它才允许 Xcode 按 App ID 现场创建 / 下载。前提是 Xcode 已在
    # 「设置 → 账户」里登录了对应 Apple ID，否则会以鉴权失败告终。
    set -- "$@" -allowProvisioningUpdates \
      CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
      "DEVELOPMENT_TEAM=$OWC_APPLE_TEAM_ID"
    ;;
  adhoc)
    # Xcode insists on a provisioning profile as soon as App Groups are present.
    # Build first, then apply a local ad-hoc signature with the generated
    # entitlements; this is sufficient for bundle-structure testing.
    set -- "$@" CODE_SIGNING_ALLOWED=NO
    ;;
  none)
    set -- "$@" CODE_SIGNING_ALLOWED=NO
    ;;
esac

"$@" build

widget_product="$derived_data/Build/Products/$configuration/OffWorkCountdownWidgetExtension.appex"
if [ ! -x "$widget_product/Contents/MacOS/OffWorkCountdownWidgetExtension" ]; then
  echo "Widget extension was not produced at $widget_product" >&2
  exit 1
fi

if [ "$signing_mode" = "adhoc" ]; then
  codesign --force --sign - --entitlements "$derived_data/Widget.entitlements" \
    "$widget_product"
fi

# ⚠️ 光看 xcodebuild 的退出码不够。增量构建认为产物是最新的时会直接跳过，于是
# 上面那个「文件存在吗」的检查会拿一个**上一次用别的模式构建出来的旧 appex**
# 通过，脚本照常报成功。实测踩过：entitlements 已经是 app-group 模式，appex 却
# 还是几天前 ad-hoc / local-support 的那份，而且是在真机验收时才发现。
#
# 因此校验产物本身是否与请求的模式一致，而不是校验命令有没有报错。
actual_storage_mode=$(plutil -extract OWCWidgetStorageMode raw -o - \
  "$widget_product/Contents/Info.plist" 2>/dev/null || echo "<missing>")
if [ "$actual_storage_mode" != "$widget_storage_mode" ]; then
  echo "Widget storage mode mismatch: built '$actual_storage_mode', expected '$widget_storage_mode'." >&2
  echo "The build was probably skipped as up-to-date. Remove $derived_data and retry." >&2
  exit 1
fi

if [ "$signing_mode" = "automatic" ]; then
  # ad-hoc 签名的 App Group 容器会被 containermanagerd 拒绝，必须确认拿到的是
  # 真实团队签名而不是回退的 ad-hoc。
  if codesign -dvv "$widget_product" 2>&1 | grep -q "flags=.*adhoc"; then
    echo "Widget was signed ad-hoc despite OWC_WIDGET_SIGNING_MODE=automatic." >&2
    exit 1
  fi
fi

# Tauri 的 bundle.macOS.files 是一张静态路径表，读不到 OWC_WIDGET_CONFIGURATION。
# 把成品放到一个与 configuration 无关的固定位置，配置里引用这个位置，否则用
# Debug 构建时 Tauri 会去 Products/Release/ 找，嵌进去一个过期的或根本不存在的
# appex——而且不会报错。
bundled_product="$derived_data/OffWorkCountdownWidgetExtension.appex"
rm -rf "$bundled_product"
cp -R "$widget_product" "$bundled_product"

echo "Built Widget extension: $widget_product"
echo "Staged for bundling: $bundled_product"
