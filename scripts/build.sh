#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
bash scripts/check.sh

mkdir -p build dist
for architecture in arm64 x86_64; do
  xcrun swiftc -O -parse-as-library -target "$architecture-apple-macos13.0" \
    -module-cache-path "build/module-cache-$architecture" \
    src/*.swift -o "build/CodexDynamicBackground-$architecture"
done
xcrun lipo -create build/CodexDynamicBackground-arm64 build/CodexDynamicBackground-x86_64 \
  -output build/CodexDynamicBackground

application_path="$project_root/dist/Codex 动态背景.app"
mkdir -p "$application_path/Contents/MacOS" "$application_path/Contents/Resources"
cp build/CodexDynamicBackground "$application_path/Contents/MacOS/"
cp src/Info.plist "$application_path/Contents/Info.plist"
cp src/helper.mjs assets/AppIcon.icns docs/使用说明.txt "$application_path/Contents/Resources/"
codesign --force --deep --sign - "$application_path"
codesign --verify --deep --strict "$application_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' src/Info.plist)"
archive_path="$project_root/dist/CodexBackdrop-$version-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$application_path" "$archive_path"
unzip -t "$archive_path" >/dev/null
echo "已构建：$application_path"
echo "安装包：$archive_path"
