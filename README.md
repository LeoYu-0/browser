# 浏览器

一个干净、无痕的原生 macOS 浏览器，基于 Swift + AppKit + WKWebView 编写。

## 功能

- Chrome 风格标签页（圆角、凸起、可关闭、可切换）
- 首页快捷方式（可增删改，最多 8 个）
- 右上角地球图标：一键打开指定网站（默认 bloxd.io，可在设置里改）
- 内置离线扫雷（断网时可玩）
- 自定义搜索引擎、浏览器语言
- 下载目录支持
- 无痕浏览：不保存历史记录、账号、Cookie（会话结束即清空）

## 设置

地址栏输入「设置」回车，可配置：

- 快捷方式（增删改）
- 右上角地球图标目标网站
- 搜索引擎（`%s` 为搜索词占位符）
- 浏览器语言
- 下载目录

## 构建

依赖：macOS + Xcode Command Line Tools（`swiftc`）。

```bash
# 编译
swiftc -O main.swift -o browser

# 打包成 .app
mkdir -p "浏览器.app/Contents/MacOS" "浏览器.app/Contents/Resources"
cp browser "浏览器.app/Contents/MacOS/浏览器"
cp 扫雷2.html "浏览器.app/Contents/Resources/扫雷2.html"
cp appicon.icns "浏览器.app/Contents/Resources/appicon.icns"

# 签名
codesign --force --deep --sign - "浏览器.app"
```

## 版本

v1.0.0
