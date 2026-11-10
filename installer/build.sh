#!/bin/bash
# 完整构建：浏览器.app → 免密安装器 → DMG
# 在仓库根目录运行：installer/build.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="浏览器"
INSTALLER_NAME="安装浏览器"
DMG_NAME="浏览器-免密安装.dmg"

# 1. 编译浏览器
echo "==> 编译浏览器"
swiftc -O main.swift -o "$APP_NAME-bin"

# 2. 组装浏览器.app
echo "==> 组装浏览器.app"
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS" "$APP_NAME.app/Contents/Resources"
cp "$APP_NAME-bin" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp 扫雷2.html "$APP_NAME.app/Contents/Resources/扫雷2.html"
cp appicon.icns "$APP_NAME.app/Contents/Resources/appicon.icns"
cp browser-Info.plist "$APP_NAME.app/Contents/Info.plist"
rm -f "$APP_NAME-bin"
codesign --force --deep --sign - "$APP_NAME.app"

# 3. 编译 installer
echo "==> 编译 installer"
swiftc -O installer/installer.swift -o installer/installer-bin

# 4. 组装 installer.app（内嵌浏览器.app）
echo "==> 组装 installer.app"
rm -rf "$INSTALLER_NAME.app"
mkdir -p "$INSTALLER_NAME.app/Contents/MacOS" "$INSTALLER_NAME.app/Contents/Resources"
cp installer/installer-bin "$INSTALLER_NAME.app/Contents/MacOS/installer"
cp installer/Info.plist "$INSTALLER_NAME.app/Contents/Info.plist"
cp appicon.icns "$INSTALLER_NAME.app/Contents/Resources/appicon.icns"
rm -f installer/installer-bin
ditto "$APP_NAME.app" "$INSTALLER_NAME.app/Contents/Resources/$APP_NAME.app"
codesign --force --deep --sign - "$INSTALLER_NAME.app"

# 5. 打包 DMG
echo "==> 打包 DMG"
rm -f "$DMG_NAME"
mkdir -p dmg-build
rm -rf dmg-build/*
cp -R "$INSTALLER_NAME.app" dmg-build/
hdiutil create -volname "$INSTALLER_NAME" -srcfolder dmg-build -ov -format UDZO "$DMG_NAME" >/dev/null 2>&1
rm -rf dmg-build
rm -rf "$APP_NAME.app" "$INSTALLER_NAME.app"

echo ""
echo "完成：$ROOT/$DMG_NAME"
ls -la "$DMG_NAME"
