#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_DIR="$ROOT_DIR/.build/real-data-smoke-bin"
mkdir -p "$BUILD_DIR"

SOURCES=(
  "$ROOT_DIR/SwiftLauncher/Models/AppSection.swift"
  "$ROOT_DIR/SwiftLauncher/Models/LauncherModels.swift"
  "$ROOT_DIR/SwiftLauncher/Models/MinecraftModels.swift"
  "$ROOT_DIR/SwiftLauncher/Support/JSONCoding.swift"
  "$ROOT_DIR/SwiftLauncher/Support/LauncherError.swift"
  "$ROOT_DIR/SwiftLauncher/Support/Hashing.swift"
  "$ROOT_DIR/SwiftLauncher/Services/JavaRuntimeService.swift"
  "$ROOT_DIR/SwiftLauncher/Services/MojangMetadataService.swift"
  "$ROOT_DIR/SwiftLauncher/Services/PublicHTTPClient.swift"
  "$ROOT_DIR/SwiftLauncher/Services/FileDownloadService.swift"
  "$ROOT_DIR/SwiftLauncher/Services/LoaderMetadataService.swift"
  "$ROOT_DIR/script/real_data_smoke.swift"
)

/usr/bin/swiftc \
  -parse-as-library \
  -swift-version 6 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$SDK_PATH" \
  -module-name SwiftLauncherRealDataSmoke \
  "${SOURCES[@]}" \
  -o "$BUILD_DIR/verify" \
  -framework CryptoKit

cd "$ROOT_DIR"
"$BUILD_DIR/verify"
