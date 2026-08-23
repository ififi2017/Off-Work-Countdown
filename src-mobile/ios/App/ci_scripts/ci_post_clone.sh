#!/bin/sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=${CI_PRIMARY_REPOSITORY_PATH:-"$SCRIPT_DIRECTORY/../../../.."}

cd "$REPOSITORY_ROOT"

NODE_MAJOR=""
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
fi

if [ "$NODE_MAJOR" != "24" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Xcode Cloud needs Homebrew to install the repository's Node.js 24 toolchain." >&2
    exit 1
  fi
  brew install node@24
  PATH="$(brew --prefix node@24)/bin:$PATH"
  export PATH
fi

echo "Preparing generated iOS resources with Node.js $(node --version)."
npm ci --ignore-scripts --no-audit --no-fund
npm run build:ios-native-rules
npm run check:ios

test -s src-mobile/ios/App/App/Resources/CountdownRules.js
