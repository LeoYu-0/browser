import AppKit
import WebKit

// 车齐星浏览器 —— 无痕标签页浏览器（Chrome 风格标签）
// 顶部：Chrome 风格标签页栏（圆角、凸起、可关闭）
// 空白新标签页：显示两个网站快捷方式卡片
// 不保存历史记录、账号、书签、Cookie 持久化（会话结束即清空）

struct Shortcut {
    let title: String
    let url: String
    let emoji: String
    let color: NSColor
}

// 设置存储：持久化快捷方式列表和 bloxd 目标网站
final class SettingsStore {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard

    private let kShortcuts = "shortcuts.list"
    private let kBloxd = "shortcut.bloxd"
    private let kSearch = "settings.search"
    private let kLang = "settings.lang"
    private let kDownload = "settings.download"

    // 存储的自定义快捷方式（标题+链接+图标）
    struct Item {
        var title: String
        var url: String
        var emoji: String
    }

    var bloxdURL: String {
        get { d.string(forKey: kBloxd) ?? "https://www.bloxd.io/" }
        set { d.set(newValue, forKey: kBloxd) }
    }

    // 搜索引擎 URL（%s 为搜索词占位符）
    var searchEngine: String {
        get { d.string(forKey: kSearch) ?? "https://www.bing.com/search?q=%s" }
        set { d.set(newValue, forKey: kSearch) }
    }

    // 浏览器语言（如 zh-CN / en-US）
    var language: String {
        get { d.string(forKey: kLang) ?? "zh-CN" }
        set { d.set(newValue, forKey: kLang) }
    }

    // 下载目录（默认 ~/Downloads）
    var downloadDir: String {
        get {
            if let v = d.string(forKey: kDownload), !v.isEmpty { return v }
            return NSHomeDirectory() + "/Downloads"
        }
        set { d.set(newValue, forKey: kDownload) }
    }

    // 读取全部自定义快捷方式
    func items() -> [Item] {
        guard let arr = d.array(forKey: kShortcuts) as? [[String: String]] else {
            // 默认值
            return [
                Item(title: "IXL", url: "https://www.ixl.com/signin/mingwan", emoji: "📚"),
                Item(title: "Toddle", url: "https://web.toddleapp.cn/platform/416851558483954744/courses", emoji: "🏫"),
            ]
        }
        return arr.map {
            Item(title: $0["title"] ?? "", url: $0["url"] ?? "", emoji: $0["emoji"] ?? "🔗")
        }
    }

    func save(_ list: [Item]) {
        let arr = list.map { ["title": $0.title, "url": $0.url, "emoji": $0.emoji] }
        d.set(arr, forKey: kShortcuts)
    }
}

// 构建当前快捷方式列表（读设置）
func buildShortcuts() -> [Shortcut] {
    let items = SettingsStore.shared.items()
    let palette: [NSColor] = [
        NSColor(calibratedRed: 0.16, green: 0.65, blue: 0.95, alpha: 1.0),
        NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.20, alpha: 1.0),
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.45, alpha: 1.0),
        NSColor(calibratedRed: 0.80, green: 0.40, blue: 0.75, alpha: 1.0),
        NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.35, alpha: 1.0),
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.90, alpha: 1.0),
    ]
    return items.enumerated().map { (i, it) in
        Shortcut(title: it.title, url: it.url, emoji: it.emoji, color: palette[i % palette.count])
    }
}

// 离线扫雷卡片：仅断网时显示
let minesweeperShortcut = Shortcut(title: "扫雷", url: "mine://offline", emoji: "💣", color: NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0))

// 下载目录入口卡片
let downloadShortcut = Shortcut(title: "下载", url: "download://open", emoji: "⬇️", color: NSColor(calibratedRed: 0.30, green: 0.65, blue: 0.45, alpha: 1.0))

let appVersion = "v1.0.0"

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = BrowserViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "浏览器"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentViewController = content
        window.center()
        window.setFrameAutosaveName("BrowserWindow")
        window.minSize = NSSize(width: 720, height: 480)
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - 单个标签（数据模型）

final class Tab {
    let webView: WKWebView
    var title: String = "新标签页"
    var isEphemeral: Bool = false  // 临时标签：失去焦点即自动关闭
    weak var tabView: TabView?

    init(config: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
    }
}

// MARK: - Chrome 风格标签视图（自绘）

final class TabView: NSView {
    var title: String = "新标签页" {
        didSet { titleLabel.stringValue = title; needsLayout = true }
    }
    var isSelected: Bool = false {
        didSet { needsDisplay = true; closeButton.contentTintColor = isSelected ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor }
    }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = true
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = true
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 11)
        closeButton.contentTintColor = NSColor.tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "关闭标签页"
        addSubview(closeButton)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let w = bounds.width
        closeButton.frame = NSRect(x: w - 8 - 16, y: (h - 16) / 2, width: 16, height: 16)
        titleLabel.frame = NSRect(x: 14, y: (h - 16) / 2, width: max(0, closeButton.frame.minX - 14 - 4), height: 16)
    }

    // 用 mouseDown 精确判断点击区域，避免手势拦截关闭按钮
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeButton.frame.insetBy(dx: -3, dy: -3).contains(p) {
            onClose?()
        } else {
            onSelect?()
        }
    }

    // 关键：让整个标签都命中 TabView 自身，避免子视图（标题/关闭按钮）拦截鼠标事件
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        // 点在标签范围内就返回 self，统一由 mouseDown 处理
        if bounds.contains(point) {
            return self
        }
        return view
    }

    @objc private func tabClicked() { onSelect?() }
    @objc private func closeClicked() { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = tabShapePath(in: bounds)
        if isSelected {
            // 选中标签：略深于内容区，形成对比
            NSColor(calibratedWhite: 0.93, alpha: 1.0).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()
    }

    private func tabShapePath(in rect: NSRect) -> NSBezierPath {
        // Chrome 风格：顶部圆角，底部平直（贴住内容区）
        let r: CGFloat = 8
        let path = NSBezierPath()
        let w = rect.width
        let h = rect.height

        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: 0, y: h - r))
        path.curve(to: NSPoint(x: r, y: h),
                   controlPoint1: NSPoint(x: 0, y: h),
                   controlPoint2: NSPoint(x: 0, y: h))
        path.line(to: NSPoint(x: w - r, y: h))
        path.curve(to: NSPoint(x: w, y: h - r),
                   controlPoint1: NSPoint(x: w, y: h),
                   controlPoint2: NSPoint(x: w, y: h))
        path.line(to: NSPoint(x: w, y: 0))
        path.close()
        return path
    }
}

// MARK: - 主控制器

final class BrowserViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {

    // 工具栏（地址栏）
    private let addressField = NSTextField()
    private var backButton = NSButton()
    private var forwardButton = NSButton()
    private var reloadButton = NSButton()
    private var newTabButton = NSButton()
    private var bloxdButton = NSButton()

    // 标签页栏
    private let tabBar = NSView()
    private var tabs: [Tab] = []
    private var currentIndex = -1
    private let tabContainer = NSView()

    // 首页
    private let homeView = NSView()
    private let contentContainer = NSView()

    private var currentTab: Tab? {
        return tabs.indices.contains(currentIndex) ? tabs[currentIndex] : nil
    }

    // MARK: - 视图

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("[debug] viewDidLoad start, view.bounds=%@", NSStringFromRect(view.bounds))
        buildToolbar()
        buildTabBar()
        buildContentContainer()
        addNewTab()
        NSLog("[debug] viewDidLoad end, tabs=%d, tabContainer.subviews=%d", tabs.count, tabContainer.subviews.count)
    }

    // MARK: - 工具栏

    private func buildToolbar() {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(bar)

        func makeButton(_ symbol: String, _ tooltip: String) -> NSButton {
            let b = NSButton()
            b.translatesAutoresizingMaskIntoConstraints = false
            b.bezelStyle = .texturedRounded
            b.isBordered = false
            if #available(macOS 11.0, *) {
                b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            }
            b.toolTip = tooltip
            b.setContentHuggingPriority(.required, for: .horizontal)
            return b
        }

        backButton = makeButton("chevron.left", "后退")
        forwardButton = makeButton("chevron.right", "前进")
        reloadButton = makeButton("arrow.clockwise", "刷新")
        newTabButton = makeButton("plus", "新建标签页")
        bloxdButton = makeButton("globe", "打开小游戏")

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "输入网址或搜索，回车访问"
        addressField.font = NSFont.systemFont(ofSize: 13)
        addressField.bezelStyle = .roundedBezel
        addressField.target = self
        addressField.action = #selector(addressEntered(_:))

        backButton.target = self
        backButton.action = #selector(backClicked(_:))
        forwardButton.target = self
        forwardButton.action = #selector(forwardClicked(_:))
        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked(_:))
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked(_:))
        bloxdButton.target = self
        bloxdButton.action = #selector(bloxdClicked(_:))

        bar.addSubview(backButton)
        bar.addSubview(forwardButton)
        bar.addSubview(reloadButton)
        bar.addSubview(addressField)
        bar.addSubview(newTabButton)
        bar.addSubview(bloxdButton)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),

            backButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            backButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 30),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 4),
            reloadButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 30),

            addressField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 10),
            addressField.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 26),

            newTabButton.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 8),
            newTabButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 30),

            bloxdButton.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: 2),
            bloxdButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            bloxdButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            bloxdButton.widthAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - 标签页栏（Chrome 风格）

    private func buildTabBar() {
        tabBar.translatesAutoresizingMaskIntoConstraints = true
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(tabBar)

        tabContainer.translatesAutoresizingMaskIntoConstraints = true
        tabBar.addSubview(tabContainer)
    }

    // MARK: - 内容容器 + 首页

    private func buildContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 74),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        buildHomeView()
    }

    private func buildHomeView() {
        homeView.translatesAutoresizingMaskIntoConstraints = false
        homeView.wantsLayer = true
        homeView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 公告横幅
        let announcement = NSTextField(labelWithString: "📢 最新版本可在 GitHub 下载")
        announcement.translatesAutoresizingMaskIntoConstraints = false
        announcement.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        announcement.textColor = NSColor.secondaryLabelColor
        announcement.alignment = .center
        homeView.addSubview(announcement)

        let title = NSTextField(labelWithString: "快捷方式")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.textColor = NSColor.labelColor
        homeView.addSubview(title)

        NSLayoutConstraint.activate([
            announcement.topAnchor.constraint(equalTo: homeView.topAnchor, constant: 24),
            announcement.centerXAnchor.constraint(equalTo: homeView.centerXAnchor),
            announcement.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            title.centerXAnchor.constraint(equalTo: homeView.centerXAnchor),
            title.bottomAnchor.constraint(equalTo: homeView.centerYAnchor, constant: -120),
        ])

        // 默认只显示常规卡片；扫雷卡片仅在用户加载网站失败（无网）时出现
        renderCards(buildShortcuts())
    }

    private func renderCards(_ list: [Shortcut]) {
        // 清除旧卡片（保留 title）
        for v in homeView.subviews {
            if v is NSTextField { continue }
            v.removeFromSuperview()
        }

        // 始终在末尾追加「下载」入口卡片
        var fullList = list
        if !fullList.contains(where: { $0.title == "下载" }) {
            fullList.append(downloadShortcut)
        }

        let cardWidth: CGFloat = 240
        let cardHeight: CGFloat = 160
        let gap: CGFloat = 28
        let count = fullList.count

        for (i, sc) in fullList.enumerated() {
            let card = makeShortcutCard(sc)
            card.translatesAutoresizingMaskIntoConstraints = false
            homeView.addSubview(card)

            let centerXOffset = (CGFloat(i) - CGFloat(count - 1) / 2.0) * (cardWidth + gap)
            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: homeView.centerXAnchor, constant: centerXOffset),
                card.centerYAnchor.constraint(equalTo: homeView.centerYAnchor),
                card.widthAnchor.constraint(equalToConstant: cardWidth),
                card.heightAnchor.constraint(equalToConstant: cardHeight),
            ])
        }
    }

    private func makeShortcutCard(_ sc: Shortcut) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.shadowOpacity = 0
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOffset = NSSize(width: 0, height: -4)
        card.layer?.shadowRadius = 12

        let icon = NSView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 28
        icon.layer?.backgroundColor = sc.color.cgColor
        card.addSubview(icon)

        let emojiLabel = NSTextField(labelWithString: sc.emoji)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = NSFont.systemFont(ofSize: 30)
        emojiLabel.alignment = .center
        icon.addSubview(emojiLabel)

        let nameLabel = NSTextField(labelWithString: sc.title)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.alignment = .center
        card.addSubview(nameLabel)

        let urlLabel = NSTextField(labelWithString: sc.url)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = NSFont.systemFont(ofSize: 10)
        urlLabel.textColor = NSColor.secondaryLabelColor
        urlLabel.alignment = .center
        urlLabel.lineBreakMode = .byTruncatingMiddle
        card.addSubview(urlLabel)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            icon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),

            emojiLabel.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),

            urlLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            urlLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            urlLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
        ])

        // 点击跳转（按标题匹配）
        let click = NSClickGestureRecognizer(target: self, action: #selector(shortcutClicked(_:)))
        click.name = sc.title
        card.addGestureRecognizer(click)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["card": card]
        )
        card.addTrackingArea(tracking)

        return card
    }

    @objc private func shortcutClicked(_ sender: NSClickGestureRecognizer) {
        guard let name = sender.name else { return }
        // 下载入口
        if name == "下载" {
            openDownloadFolder()
            return
        }
        guard let sc = buildShortcuts().first(where: { $0.title == name }) else { return }
        if sc.url == "mine://offline" {
            openOfflineMinesweeper()
        } else {
            navigate(to: sc.url)
        }
    }

    // 用 Finder 打开下载目录
    private func openDownloadFolder() {
        let dir = SettingsStore.shared.downloadDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir)
        NSWorkspace.shared.open(url)
    }

    // 打开内置的离线扫雷
    private func openOfflineMinesweeper() {
        guard let tab = currentTab else { return }
        if let url = Bundle.main.url(forResource: "扫雷2", withExtension: "html") {
            showWebView(tab)
            tab.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = Bundle.main.url(forResource: "扫雷2", withExtension: "html", subdirectory: nil) {
            showWebView(tab)
            tab.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo, let card = info["card"] as? NSView else { return }
        card.layer?.shadowOpacity = 0.18
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.04).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo, let card = info["card"] as? NSView else { return }
        card.layer?.shadowOpacity = 0
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    // MARK: - 标签页管理

    private func addNewTab() {
        // 标签页数量上限
        if tabs.count >= 10 {
            NSSound.beep()
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let tab = Tab(config: config)
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tabs.append(tab)

        let idx = tabs.count - 1
        let tv = TabView(frame: .zero)
        tv.title = "新标签页"
        tv.translatesAutoresizingMaskIntoConstraints = true
        // 捕获 tab 对象，动态查索引（避免关闭标签后索引错位）
        tv.onSelect = { [weak self, weak tab] in
            guard let self = self, let tab = tab,
                  let i = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.selectTab(at: i)
        }
        tv.onClose = { [weak self, weak tab] in
            guard let self = self, let tab = tab,
                  let i = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.closeTab(at: i)
        }
        tab.tabView = tv
        tabContainer.addSubview(tv)

        relayoutTabs()
        selectTab(at: idx)
        showHome()
    }

    private func relayoutTabs() {
        // 手动 frame 布局：标签靠左排列，等宽，像 Chrome 一样
        let count = tabContainer.subviews.count
        guard count > 0 else { return }

        let availableWidth = max(tabContainer.bounds.width, 100)
        let spacing: CGFloat = 2
        let totalSpacing = spacing * CGFloat(count - 1)
        let tabWidth = min(200, max(90, (availableWidth - totalSpacing) / CGFloat(count)))
        let tabHeight = tabContainer.bounds.height

        var x: CGFloat = 0
        for v in tabContainer.subviews {
            v.frame = NSRect(x: x, y: 0, width: tabWidth, height: tabHeight)
            x += tabWidth + spacing
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height

        // 注意：NSView 默认坐标系原点在左下角，标签栏应在顶部
        // 标签栏：顶部 34pt
        tabBar.frame = NSRect(x: 0, y: h - 34, width: w, height: 34)
        // 标签容器：左侧留出 80pt 给红黄绿窗口按钮
        tabContainer.frame = NSRect(x: 80, y: 0, width: w - 88, height: 34)

        relayoutTabs()
    }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }

        // 如果切到的是非临时标签，且当前有临时标签，自动关闭临时标签
        if let target = tabs.indices.contains(index) ? tabs[index] : nil,
           !target.isEphemeral {
            closeEphemeralTabs()
        }

        guard tabs.indices.contains(index) else { return }
        currentIndex = index

        for (i, tab) in tabs.enumerated() {
            tab.tabView?.isSelected = (i == index)
        }

        let tab = tabs[index]
        if tab.webView.url != nil {
            showWebView(tab)
        } else {
            showHome()
        }
        updateNavButtons()
    }

    // 关闭所有临时标签
    private func closeEphemeralTabs() {
        let ephemeralIndices = tabs.indices.filter { tabs[$0].isEphemeral }
        // 从后往前关闭，避免索引错乱
        for idx in ephemeralIndices.reversed() {
            let tab = tabs[idx]
            tab.tabView?.removeFromSuperview()
            tab.webView.stopLoading()
            tabs.remove(at: idx)
        }
        if !ephemeralIndices.isEmpty {
            relayoutTabs()
            // 修正 currentIndex
            if currentIndex >= tabs.count {
                currentIndex = tabs.count - 1
            }
        }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        tab.tabView?.removeFromSuperview()
        tab.webView.stopLoading()
        tabs.remove(at: index)

        if tabs.isEmpty {
            currentIndex = -1
            showHome()
            // 至少保留一个空白标签
            addNewTab()
            return
        }
        if index == currentIndex {
            let newIdx = min(index, tabs.count - 1)
            selectTab(at: newIdx)
        } else if index < currentIndex {
            currentIndex -= 1
            selectTab(at: currentIndex)
        }
        relayoutTabs()
    }

    private func showHome() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(homeView)
        NSLayoutConstraint.activate([
            homeView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            homeView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            homeView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            homeView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        addressField.stringValue = ""
    }

    private func showWebView(_ tab: Tab) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(tab.webView)
        tab.webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tab.webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tab.webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tab.webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tab.webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        if let url = tab.webView.url {
            addressField.stringValue = url.absoluteString
        }
    }

    @objc private func newTabClicked(_ sender: Any) {
        addNewTab()
        view.window?.makeFirstResponder(addressField)
    }

    @objc private func bloxdClicked(_ sender: Any) {
        // 如果已有一个 Bloxd 临时标签，直接切过去
        if let idx = tabs.firstIndex(where: { $0.isEphemeral }) {
            selectTab(at: idx)
            return
        }
        // 否则新建一个临时标签并加载目标网站（可配置）
        let idx = addEphemeralTab(url: SettingsStore.shared.bloxdURL)
        selectTab(at: idx)
    }

    // 新建一个临时标签（不参与常规切换，失去焦点即关闭）
    @discardableResult
    private func addEphemeralTab(url: String) -> Int {
        // 标签页数量上限
        if tabs.count >= 10 {
            NSSound.beep()
            return currentIndex
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let tab = Tab(config: config)
        tab.isEphemeral = true
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tabs.append(tab)

        let idx = tabs.count - 1
        let tv = TabView(frame: .zero)
        tv.title = "小游戏"
        tv.translatesAutoresizingMaskIntoConstraints = true
        tv.onSelect = { [weak self, weak tab] in
            guard let self = self, let tab = tab,
                  let i = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.selectTab(at: i)
        }
        tv.onClose = { [weak self, weak tab] in
            guard let self = self, let tab = tab,
                  let i = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.closeTab(at: i)
        }
        tab.tabView = tv
        tabContainer.addSubview(tv)

        relayoutTabs()
        if let u = URL(string: url) {
            var req = URLRequest(url: u)
            req.setValue(SettingsStore.shared.language, forHTTPHeaderField: "Accept-Language")
            tab.webView.load(req)
        }
        return idx
    }

    // MARK: - 导航

    @objc private func addressEntered(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        navigate(to: text)
    }

    @objc private func backClicked(_ sender: Any) {
        guard let tab = currentTab, tab.webView.canGoBack else { return }
        tab.webView.goBack()
    }

    @objc private func forwardClicked(_ sender: Any) {
        guard let tab = currentTab, tab.webView.canGoForward else { return }
        tab.webView.goForward()
    }

    @objc private func reloadClicked(_ sender: Any) {
        guard let tab = currentTab else { return }
        if tab.webView.url != nil { tab.webView.reload() }
    }

    private func navigate(to input: String) {
        guard let tab = currentTab else { return }

        // 输入「设置」打开设置面板
        if input == "设置" || input.lowercased() == "settings" {
            openSettings()
            return
        }

        var urlString = input
        if input.contains(" ") || !input.contains(".") {
            // 使用自定义搜索引擎
            if let q = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let engine = SettingsStore.shared.searchEngine
                urlString = engine.contains("%s") ? engine.replacingOccurrences(of: "%s", with: q) : engine + q
            }
        } else if !input.lowercased().hasPrefix("http://") && !input.lowercased().hasPrefix("https://") {
            urlString = "https://" + input
        }
        guard let url = URL(string: urlString) else { return }
        showWebView(tab)
        var req = URLRequest(url: url)
        req.setValue(SettingsStore.shared.language, forHTTPHeaderField: "Accept-Language")
        tab.webView.load(req)
    }

    private func updateNavButtons() {
        guard let tab = currentTab else {
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            return
        }
        backButton.isEnabled = tab.webView.canGoBack
        forwardButton.isEnabled = tab.webView.canGoForward
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncFromWebView(webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncFromWebView(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        showErrorPage(error)
        updateNavButtons()

        // 如果是网络相关错误（无网），在首页显示离线扫雷卡片
        if isNetworkError(ns) {
            showOfflineMinesweeperCard()
        }
    }

    // 判断是否是无网/网络错误
    private func isNetworkError(_ ns: NSError) -> Bool {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorTimedOut,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }

    // 在首页追加离线扫雷卡片
    private func showOfflineMinesweeperCard() {
        var all = buildShortcuts()
        if !all.contains(where: { $0.title == minesweeperShortcut.title }) {
            all.append(minesweeperShortcut)
        }
        renderCards(all)
    }

    private func syncFromWebView(_ webView: WKWebView) {
        guard let tab = tabs.first(where: { $0.webView === webView }) else { return }
        if let title = webView.title, !title.isEmpty {
            tab.title = title
            tab.tabView?.title = title
        }
        if tab.webView === currentTab?.webView {
            if let url = webView.url, url.absoluteString != "about:blank" {
                addressField.stringValue = url.absoluteString
            }
        }
        updateNavButtons()
    }

    private func showErrorPage(_ error: Error) {
        let ns = error as NSError
        let msg = ns.localizedDescription
        let html = """
        <html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f7;color:#333}
        .box{text-align:center;max-width:520px;padding:40px}
        h1{font-size:22px;font-weight:600}
        p{font-size:14px;color:#666;line-height:1.6}
        </style></head><body><div class="box">
        <h1>无法打开此页面</h1>
        <p>\(msg)</p>
        <p>请检查网址是否拼写正确，或检查网络连接。</p>
        </div></body></html>
        """
        currentTab?.webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - 下载支持

    // 响应转为下载
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // 指定下载保存位置
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = SettingsStore.shared.downloadDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dest = URL(fileURLWithPath: dir).appendingPathComponent(suggestedFilename)
        completionHandler(dest)
    }

    // 下载完成
    func download(_ download: WKDownload, didFinishDownloadingTo location: URL) {
        NSLog("[download] 完成：%@", location.path)
    }

    // 下载失败
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        NSLog("[download] 失败：%@", error.localizedDescription)
    }

    // 私有回调：批准 Pointer Lock 请求（macOS WKWebView 默认拒绝，必须实现此方法才生效）
    @objc(_webViewDidRequestPointerLock:completionHandler:)
    func _webViewDidRequestPointerLock(_ webView: WKWebView, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    // MARK: - 设置面板

    private func openSettings() {
        guard let tab = currentTab else { return }

        // 确保 webView 已注册消息处理器
        let config = tab.webView.configuration
        config.userContentController.removeScriptMessageHandler(forName: "settings")
        config.userContentController.add(self, name: "settings")

        showWebView(tab)
        tab.webView.loadHTMLString(settingsHTML(), baseURL: nil)
    }

    private func settingsHTML() -> String {
        let s = SettingsStore.shared
        let bloxd = s.bloxdURL.replacingOccurrences(of: "\"", with: "&quot;")
        let search = s.searchEngine.replacingOccurrences(of: "\"", with: "&quot;")
        let lang = s.language.replacingOccurrences(of: "\"", with: "&quot;")
        let download = s.downloadDir.replacingOccurrences(of: "\"", with: "&quot;")

        // 序列化现有快捷方式到 JSON（供 JS 渲染）
        var itemsJSON = "[]"
        if let data = try? JSONSerialization.data(withJSONObject: s.items().map { ["title": $0.title, "url": $0.url, "emoji": $0.emoji] }, options: []),
           let str = String(data: data, encoding: .utf8) {
            itemsJSON = str
        }

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body{font-family:-apple-system,'PingFang SC',sans-serif;background:#f5f5f7;color:#1d1d1f;margin:0;padding:32px;max-width:680px;margin:0 auto;}
        h1{font-size:22px;font-weight:700;margin:0 0 24px;}
        .card{background:#fff;border-radius:12px;padding:20px 24px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,0.06);}
        .card h2{font-size:15px;font-weight:600;margin:0 0 16px;color:#1d1d1f;}
        label{display:block;font-size:12px;color:#6e6e73;margin-bottom:6px;}
        input{width:100%;box-sizing:border-box;font-size:13px;padding:8px 10px;border:1px solid #d2d2d7;border-radius:8px;margin-bottom:10px;font-family:inherit;}
        input:focus{outline:none;border-color:#0071e3;}
        .btn{background:#0071e3;color:#fff;border:none;border-radius:8px;padding:9px 18px;font-size:13px;cursor:pointer;font-family:inherit;}
        .btn:hover{background:#0077ed;}
        .btn.ghost{background:#f2f2f7;color:#0071e3;}
        .sc-item{display:flex;gap:8px;align-items:flex-start;margin-bottom:10px;}
        .sc-item input.emoji{width:52px;flex:0 0 52px;text-align:center;}
        .sc-item input.title{flex:1;}
        .sc-item input.url{flex:2;}
        .sc-del{flex:0 0 32px;width:32px;height:32px;border-radius:8px;border:none;background:#ffecec;color:#e53935;cursor:pointer;font-size:16px;line-height:1;}
        .sc-del:hover{background:#ffdada;}
        .row{display:flex;gap:8px;margin-bottom:12px;}
        .row input{flex:1;margin-bottom:0;}
        .about{text-align:center;color:#6e6e73;font-size:12px;padding:20px 0;}
        .about .ver{font-size:15px;color:#1d1d1f;font-weight:600;margin-bottom:4px;}
        .hint{font-size:12px;color:#8e8e93;margin-top:4px;}
        </style></head><body>
        <h1>设置</h1>

        <div class="card">
        <h2>快捷方式</h2>
        <div id="list"></div>
        <button class="btn ghost" onclick="addRow()">＋ 添加快捷方式</button>
        <div class="hint">图标可填 emoji（如 📚），标题和链接必填</div>
        </div>

        <div class="card">
        <h2>右上角地球图标</h2>
        <label>目标网站</label>
        <input id="bloxd" type="text" value="\(bloxd)">
        </div>

        <div class="card">
        <h2>搜索引擎</h2>
        <label>搜索链接（%s 为搜索词占位符）</label>
        <input id="search" type="text" value="\(search)">
        <div class="hint">例：https://www.baidu.com/s?wd=%s 或 https://www.google.com/search?q=%s</div>
        </div>

        <div class="card">
        <h2>浏览器语言</h2>
        <label>选择语言</label>
        <select id="lang" style="width:100%;box-sizing:border-box;font-size:13px;padding:8px 10px;border:1px solid #d2d2d7;border-radius:8px;font-family:inherit;background:#fff;">
        <option value="zh-CN">简体中文</option>
        <option value="zh-TW">繁體中文</option>
        <option value="en-US">English</option>
        <option value="ja-JP">日本語</option>
        <option value="ko-KR">한국어</option>
        </select>
        </div>

        <div class="card">
        <h2>下载目录</h2>
        <label>下载文件保存位置</label>
        <input id="download" type="text" value="\(download)">
        <div class="hint">默认 ~/Downloads</div>
        </div>

        <div class="card">
        <button class="btn" onclick="save()">保存</button>
        <span id="saved" style="margin-left:12px;color:#34c759;font-size:13px;display:none;">已保存 ✓</span>
        </div>

        <div class="about">
        <div class="ver">关于此浏览器</div>
        <div>版本 \(appVersion)</div>
        </div>

        <script>
        var items = \(itemsJSON);
        var listEl = document.getElementById('list');

        // 设置语言下拉框默认选中当前语言
        (function(){
            var cur = '\(lang)';
            var sel = document.getElementById('lang');
            for (var i=0; i<sel.options.length; i++) {
                if (sel.options[i].value === cur) { sel.selectedIndex = i; break; }
            }
        })();

        function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

        function render() {
            listEl.innerHTML = '';
            items.forEach(function(it, i) {
                var div = document.createElement('div');
                div.className = 'sc-item';
                div.innerHTML =
                    '<input class="emoji" type="text" value="' + esc(it.emoji) + '" data-i="'+i+'" data-k="emoji">' +
                    '<input class="title" type="text" placeholder="标题" value="' + esc(it.title) + '" data-i="'+i+'" data-k="title">' +
                    '<input class="url" type="text" placeholder="https://..." value="' + esc(it.url) + '" data-i="'+i+'" data-k="url">' +
                    '<button class="sc-del" data-i="'+i+'" title="删除">✕</button>';
                listEl.appendChild(div);
            });
            // 绑定删除
            listEl.querySelectorAll('.sc-del').forEach(function(b) {
                b.onclick = function() {
                    items.splice(parseInt(b.getAttribute('data-i')), 1);
                    render();
                };
            });
            // 绑定输入
            listEl.querySelectorAll('input').forEach(function(inp) {
                inp.oninput = function() {
                    var i = parseInt(inp.getAttribute('data-i'));
                    var k = inp.getAttribute('data-k');
                    items[i][k] = inp.value;
                };
            });
        }

        function addRow() {
            if (items.length >= 8) { alert('最多只能添加 8 个快捷方式'); return; }
            items.push({title:'', url:'', emoji:'🔗'});
            render();
            listEl.lastElementChild.querySelector('.title').focus();
        }

        function save() {
            // 过滤掉标题和链接都为空的行
            var cleaned = items.filter(function(it){ return it.title.trim() || it.url.trim(); });
            var data = {
                items: cleaned,
                bloxd: document.getElementById('bloxd').value.trim(),
                search: document.getElementById('search').value.trim(),
                lang: document.getElementById('lang').value.trim(),
                download: document.getElementById('download').value.trim()
            };
            window.webkit.messageHandlers.settings.postMessage(data);
            var el = document.getElementById('saved');
            el.style.display = 'inline';
            setTimeout(function(){ el.style.display = 'none'; }, 2000);
        }

        render();
        </script>
        </body></html>
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "settings", let body = message.body as? [String: Any] else { return }
        let s = SettingsStore.shared

        // 保存快捷方式列表
        if let itemsArr = body["items"] as? [[String: String]] {
            var newItems: [SettingsStore.Item] = []
            for it in itemsArr {
                if newItems.count >= 8 { break }  // 快捷方式上限 8 个
                let title = (it["title"] ?? "").trimmingCharacters(in: .whitespaces)
                let url = (it["url"] ?? "").trimmingCharacters(in: .whitespaces)
                let emoji = (it["emoji"] ?? "🔗").trimmingCharacters(in: .whitespaces)
                if title.isEmpty && url.isEmpty { continue }
                newItems.append(SettingsStore.Item(title: title.isEmpty ? "链接" : title,
                                                   url: url,
                                                   emoji: emoji.isEmpty ? "🔗" : emoji))
            }
            s.save(newItems)
        }

        if let v = body["bloxd"] as? String, !v.isEmpty { s.bloxdURL = v }
        if let v = body["search"] as? String, !v.isEmpty { s.searchEngine = v }
        if let v = body["lang"] as? String, !v.isEmpty { s.language = v }
        if let v = body["download"] as? String, !v.isEmpty { s.downloadDir = v }

        // 刷新首页卡片
        renderCards(buildShortcuts())
    }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "退出浏览器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

app.run()
