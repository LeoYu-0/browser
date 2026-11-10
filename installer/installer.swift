import AppKit
import Foundation

// 自安装器：把内嵌的「浏览器.app」装到 ~/Applications，全程不需要管理员密码。
// 双击即装，装完可选择直接打开。

let fm = FileManager.default

// 弹窗失败并退出
func fail(_ title: String, _ msg: String) -> Never {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = msg
    alert.alertStyle = .warning
    alert.addButton(withTitle: "好")
    alert.runModal()
    exit(1)
}

// 安装完成提示
func done(_ destPath: String) -> Never {
    let alert = NSAlert()
    alert.messageText = "安装完成 ✓"
    alert.informativeText = "浏览器已安装到：\n\(destPath)\n\n无需管理员密码，全程自动完成。"
    alert.alertStyle = .informational
    alert.addButton(withTitle: "打开浏览器")
    alert.addButton(withTitle: "关闭")
    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(fileURLWithPath: destPath))
    }
    exit(0)
}

// 主流程
let app = NSApplication.shared
app.setActivationPolicy(.regular)
if #available(macOS 14.0, *) {
    NSApp.activate()
} else {
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
}

// 1. 找到内嵌的浏览器.app
guard let bundled = Bundle.main.url(forResource: "浏览器", withExtension: "app") else {
    fail("安装失败", "在安装包里找不到浏览器应用，安装包可能已损坏。")
}

// 2. 目标目录 ~/Applications
let home = fm.homeDirectoryForCurrentUser
let appsDir = home.appendingPathComponent("Applications")
let dest = appsDir.appendingPathComponent("浏览器.app")

// 3. 创建 ~/Applications（若不存在）
do {
    try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
} catch {
    fail("安装失败", "无法创建目录 \(appsDir.path)：\n\(error.localizedDescription)")
}

// 4. 覆盖旧版本
if fm.fileExists(atPath: dest.path) {
    do {
        try fm.removeItem(at: dest)
    } catch {
        fail("安装失败", "无法覆盖旧版本 \(dest.path)：\n\(error.localizedDescription)")
    }
}

// 5. 用 ditto 复制（保留签名与 bundle 结构）
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
p.arguments = [bundled.path, dest.path]
do {
    try p.run()
    p.waitUntilExit()
} catch {
    fail("安装失败", "复制应用失败：\n\(error.localizedDescription)")
}
guard p.terminationStatus == 0 else {
    fail("安装失败", "复制应用失败（退出码 \(p.terminationStatus)）。")
}

// 6. 提示完成
done(dest.path)
