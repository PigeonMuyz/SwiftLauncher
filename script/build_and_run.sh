#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SwiftLauncher"
BUNDLE_ID="dev.huangtianchen.SwiftLauncher"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

stop_existing_app() {
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
}

stop_existing_app

build_with_xcode() {
  if [[ "${SWIFTLAUNCHER_FORCE_DIRECT:-0}" == "1" ]]; then
    return 1
  fi
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    local candidate
    for candidate in \
      "/Applications/Xcode.app/Contents/Developer" \
      "/Applications/Xcode-beta.app/Contents/Developer"; do
      if [[ -x "$candidate/usr/bin/xcodebuild" ]]; then
        developer_dir="$candidate"
        break
      fi
    done
  fi
  if [[ -x "$developer_dir/usr/bin/xcodebuild" ]] && DEVELOPER_DIR="$developer_dir" xcodebuild -version >/dev/null 2>&1; then
    local derived="$ROOT_DIR/.build/xcode"
    DEVELOPER_DIR="$developer_dir" xcodebuild \
      -project "$ROOT_DIR/SwiftLauncher.xcodeproj" \
      -scheme SwiftLauncher \
      -configuration Debug \
      -derivedDataPath "$derived" \
      CODE_SIGNING_ALLOWED=NO \
      build
    APP_BUNDLE="$derived/Build/Products/Debug/$APP_NAME.app"
    return 0
  fi
  return 1
}

build_with_command_line_tools() {
  cd "$ROOT_DIR"
  local sdk_path="$({ xcrun --sdk macosx --show-sdk-path; } 2>/dev/null)"
  local direct_build="$ROOT_DIR/.build/direct"
  local build_binary="$direct_build/$APP_NAME"
  local swift_files=()
  while IFS= read -r -d '' file; do
    swift_files+=("$file")
  done < <(find "$ROOT_DIR/SwiftLauncher" -name '*.swift' -type f -print0 | sort -z)

  mkdir -p "$direct_build"
  /usr/bin/swiftc \
    -parse-as-library \
    -swift-version 6 \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$sdk_path" \
    -module-name SwiftLauncher \
    "${swift_files[@]}" \
    -o "$build_binary" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Security \
    -framework CryptoKit
  local contents="$APP_BUNDLE/Contents"
  local macos="$contents/MacOS"
  local plist="$contents/Info.plist"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$macos"
  cp "$build_binary" "$macos/$APP_NAME"
  chmod +x "$macos/$APP_NAME"

  plutil -create xml1 "$plist"
  plutil -insert CFBundleExecutable -string "$APP_NAME" "$plist"
  plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$plist"
  plutil -insert CFBundleName -string "$APP_NAME" "$plist"
  plutil -insert CFBundlePackageType -string APPL "$plist"
  plutil -insert LSMinimumSystemVersion -string 14.0 "$plist"
  plutil -insert NSPrincipalClass -string NSApplication "$plist"

  if [[ -d "$ROOT_DIR/SwiftLauncher/Resources" ]]; then
    mkdir -p "$contents/Resources"
    cp -R "$ROOT_DIR/SwiftLauncher/Resources/." "$contents/Resources/"
  fi
}

if ! build_with_xcode; then
  build_with_command_line_tools
fi

APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
