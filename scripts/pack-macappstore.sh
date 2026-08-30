#!/bin/sh

set -eu

# 把已签名的 .app 打成可提交 App Store 的 .pkg。
#
# App Store Connect 只收 .pkg，不收 .app；而这个 .pkg 必须用 **Mac Installer
# Distribution** 证书签（钥匙串里的身份名是历史遗留的
# "3rd Party Mac Developer Installer"，不叫门户上那个名字），与签 .app 用的
# Apple Distribution 是两张不同的证书。
#
# ⚠️ 这里刻意不重签 .app。它内部的嵌套 .appex 各自带着自己的描述文件和签名，
# 重签一次就可能把它们打乱——排查过一整轮，见 docs/PLAN-MSSTORE.md 9.11。
# productbuild 只是把已签好的包装进安装器。

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
# 不写死 target/release：带 --target 构建时（Universal 用
# --target universal-apple-darwin）产物在 target/<triple>/release/ 下。取最新的一个。
if [ -n "${1:-}" ]; then
  app_path=$1
else
  # ⚠️ maxdepth 至少 5：target/release/... 是 4 层，而带 --target 时
  # target/<triple>/release/... 是 5 层。写 4 会把 Universal 产物整个漏掉，
  # 然后安静地拿旧的单架构包去打 .pkg——踩过一次。
  app_path=$(find "$project_root/src-tauri/target" \
    -maxdepth 5 -type d \( -path "*/release/bundle/macos/DoneAt.app" -o -path "*/release/bundle/macos/Off Work Countdown.app" \) \
    -exec stat -f "%m %N" {} + 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi
output=${OWC_PKG_OUTPUT:-"${app_path%/*}/DoneAt.pkg"}
installer_identity=${OWC_INSTALLER_IDENTITY:-}

if [ ! -d "$app_path" ]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

if [ -z "$installer_identity" ]; then
  # 名称里带 Team ID，多团队时不会选错。
  installer_identity=$(security find-identity -v 2>/dev/null \
    | grep "3rd Party Mac Developer Installer" \
    | head -1 \
    | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$installer_identity" ]; then
  echo "No 'Mac Installer Distribution' certificate found in the keychain." >&2
  echo "Create one in the developer portal, or set OWC_INSTALLER_IDENTITY." >&2
  exit 1
fi

# 提交前拦住最常见的两类退件，别等上传后收拒信。
for bundle in "$app_path" "$app_path"/Contents/PlugIns/*.appex; do
  [ -e "$bundle" ] || continue
  if codesign -d --entitlements - "$bundle" 2>&1 | grep -q "get-task-allow"; then
    echo "$bundle carries get-task-allow; it was signed for development." >&2
    exit 1
  fi
  if codesign -dvv "$bundle" 2>&1 | grep -q "flags=.*adhoc"; then
    echo "$bundle is ad-hoc signed." >&2
    exit 1
  fi
done

codesign --verify --deep --strict "$app_path"

# Mac App Store 拒收宿主签名里未加 Team ID 的 iOS 式 group.*（409）。
node "$script_dir/macos-app-group-identifier.mjs" --check-bundle "$app_path" \
  --team-id "${OWC_APPLE_TEAM_ID:-}"

rm -f "$output"
productbuild \
  --component "$app_path" /Applications \
  --sign "$installer_identity" \
  "$output"

echo "Signed with: $installer_identity"
echo "Built: $output"
