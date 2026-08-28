#!/bin/bash
# 构建 release 二进制并打包为 dist/ToolBar.app + dist/ToolBar.dmg
# 为避免 macOS Launch Services 缓存旧包：清旧产物、bump CFBundleVersion、
# 拷贝后重签（ad-hoc）并向 lsregister 重新注册。
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. 清掉旧产物，避免增量构建认为没有变化
rm -f .build/arm64-apple-macosx/release/ToolBar
rm -f .build/x86_64-apple-macosx/release/ToolBar
rm -rf dist/ToolBar.app

# 分别编译 Apple Silicon 与 Intel，再 lipo 合成通用二进制
swift build -c release --arch arm64
swift build -c release --arch x86_64

# 2. 组装 .app
APP_DIR="dist/ToolBar.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create \
    .build/arm64-apple-macosx/release/ToolBar \
    .build/x86_64-apple-macosx/release/ToolBar \
    -output "$APP_DIR/Contents/MacOS/ToolBar"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# 3. 清扩展属性 + 对整个 bundle 做 ad-hoc 重签，让系统识别为新包
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# 4. 刷新 Launch Services 注册（图标 / Info 缓存）
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$PWD/$APP_DIR"

# 5. 打 DMG：.app + Applications 快捷方式，方便拖进应用程序
DMG="dist/ToolBar.dmg"
STAGE="dist/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/ToolBar.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ToolBar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# 6. 打印验证信息
echo "Built $APP_DIR"
echo "Built $DMG"
echo "--- binary ---"
ls -la "$APP_DIR/Contents/MacOS/ToolBar"
lipo -info "$APP_DIR/Contents/MacOS/ToolBar"
shasum -a 256 "$APP_DIR/Contents/MacOS/ToolBar"
echo "--- dmg ---"
ls -la "$DMG"
shasum -a 256 "$DMG"
echo "--- codesign ---"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | grep -E "Identifier|Format|Version|TeamIdentifier|Signature" || true
echo "--- bundle version ---"
plutil -p "$APP_DIR/Contents/Info.plist" | grep -E "CFBundleShortVersionString|CFBundleVersion|CFBundleIconFile"
