import AppKit
import SwiftUI
import QuotaCore

@MainActor final class Monitor: ObservableObject {
    @Published var usage: Usage?
    @Published var message = "点击登录，授权读取 Codex 额度"
    @Published var updated: Date?
    @Published var loading = false
    @Published var theme = IslandTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .dark
    @Published var stale = true
    @Published var now = Date()
    @Published var userCode: String?
    @Published var authorizing = false
    @Published var signedIn = false
    private var session: LoginSession?
    private var nextRefresh = Date.distantPast
    private var failures = 0
    private var generation = 0
    private var timer: Timer?
    private var loginTask: Task<Void, Never>?
    var headline: String {
        guard let window = usage?.rateLimit?.windows.first else { return signedIn ? "—" : "登录" }
        return "\(Int(window.remaining))%"
    }
    func start() {
        do { session = try CredentialStore.load(); signedIn = session != nil }
        catch { message = error.localizedDescription }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if let updated = self.updated, Date().timeIntervalSince(updated) > 300 { self.stale = true }
                if Date() >= self.nextRefresh { await self.refresh() }
            }
        }
        Task { await refresh() }
    }
    func login() {
        guard !authorizing else { return }
        generation += 1
        authorizing = true; message = "正在申请官方授权码…"
        loginTask = Task {
            defer { authorizing = false; userCode = nil }
            do {
                let auth = DeviceAuthorization()
                let code = try await auth.start()
                try Task.checkCancellation()
                userCode = code.userCode
                message = "在官方页面输入授权码；请勿分享此码"
                NSWorkspace.shared.open(URL(string: "https://auth.openai.com/codex/device")!)
                let result = try await auth.complete(code)
                try Task.checkCancellation()
                try CredentialStore.save(result)
                session = result; signedIn = true; usage = nil; updated = nil
                nextRefresh = .distantPast
                authorizing = false; userCode = nil
                await refresh()
            } catch is CancellationError { message = "已取消登录" }
            catch { message = "授权失败，请重试。\((error as? LoginError)?.localizedDescription ?? "请检查网络连接。")" }
        }
    }
    func cancelLogin() { loginTask?.cancel() }
    func logout() {
        loginTask?.cancel(); generation += 1
        session = nil; signedIn = false; usage = nil; updated = nil; stale = true
        do { try CredentialStore.remove(); message = "已退出并删除本应用登录文件" }
        catch { message = "已退出，但登录文件删除失败，请检查文件权限。" }
    }
    func refresh() async {
        guard !loading, !authorizing, let current = session else { return }
        loading = true
        let revision = generation
        defer { loading = false }
        do {
            let result: Usage
            do { result = try await UsageClient().fetch(credentials: current.credentials) }
            catch MonitorError.unauthorized {
                let renewed = try await DeviceAuthorization().refresh(current)
                guard revision == generation else { return }
                session = renewed
                try CredentialStore.save(renewed)
                result = try await UsageClient().fetch(credentials: renewed.credentials)
            }
            guard revision == generation else { return }
            usage = result; updated = Date(); stale = false; failures = 0
            message = result.rows.isEmpty ? "接口未提供额度窗口" : "已同步 · \(result.planType?.uppercased() ?? "Codex")"
            nextRefresh = Date().addingTimeInterval(120)
        } catch {
            guard revision == generation else { return }
            failures += 1; stale = true
            message = (error as? MonitorError)?.localizedDescription ?? (error as? LoginError)?.localizedDescription ?? "网络连接失败，将自动重试"
            nextRefresh = Date().addingTimeInterval(900)
        }
    }
}

struct IslandView: View {
    @ObservedObject var model: Monitor
    var resetText: String {
        guard let reset = model.usage?.rateLimit?.windows.first?.resetAt else { return "重置 —" }
        let remaining = reset - model.now.timeIntervalSince1970
        guard remaining > 0 else { return "待重置" }
        let mins = Int(ceil(remaining / 60))
        if mins >= 1440 { return "重置 \(mins / 1440)天\(mins % 1440 / 60)时" }
        return "重置 \(mins / 60)时\(mins % 60)分"
    }
    var body: some View {
        HStack(spacing: 8) {
            Text("Codex").font(.system(size: 11, weight: .semibold))
            if model.authorizing {
                if let code = model.userCode {
                    Button(code) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).help("点击复制授权码，然后在官方页面确认")
                } else { Text("申请授权中…").font(.system(size: 10)) }
                Spacer(minLength: 0)
                Button("取消") { model.cancelLogin() }.font(.system(size: 10))
            } else if model.signedIn {
                Text(model.usage?.planLabel ?? "—")
                    .font(.system(size: 10, weight: .medium)).opacity(0.85)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 78, alignment: .leading)
                    .help(model.usage?.planLabel ?? "套餐未知")
                Text(model.headline + (model.stale ? "*" : ""))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .fixedSize().accessibilityLabel("剩余额度 \(model.headline)\(model.stale ? "，数据已过期" : "")")
                    .help("剩余额度" + (model.stale ? " · 数据已过期" : ""))
                Spacer(minLength: 0)
                Text(resetText).font(.system(size: 10)).monospacedDigit().opacity(0.85)
                    .lineLimit(1).fixedSize().layoutPriority(1)
                    .help(model.usage?.rateLimit?.windows.first?.resetAt.map { Date(timeIntervalSince1970: $0).formatted() } ?? "重置时间未知")
            } else {
                Text("登录查看额度").font(.system(size: 10)).opacity(0.7)
                Spacer(minLength: 0)
                Button("登录") { model.login() }.font(.system(size: 11, weight: .medium))
            }
            Rectangle().fill(model.theme.ink.opacity(0.16)).frame(width: 1, height: 11)
            Button { Task { await model.refresh() } } label: {
                Image(systemName: model.loading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium)).frame(width: 20, height: 24)
            }.disabled(model.loading || !model.signedIn || model.authorizing)
                .accessibilityLabel(model.loading ? "正在刷新额度" : "刷新额度")
                .help("刷新额度")
        }
        .buttonStyle(.plain)
        .padding(.leading, 12).padding(.trailing, 5)
        .frame(width: 330, height: 28)
        .foregroundStyle(model.theme.ink)
        .modifier(ThemeSurface(theme: model.theme))
        .help(model.message)
        .contextMenu {
            ForEach(IslandTheme.allCases, id: \.self) { theme in
                Button {
                    model.theme = theme
                    UserDefaults.standard.set(theme.rawValue, forKey: "theme")
                } label: {
                    if theme == model.theme { Label(theme.rawValue, systemImage: "checkmark") }
                    else { Text(theme.rawValue) }
                }
            }
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = Monitor()
    var panel: IslandPanel!
    var status: NSStatusItem!
    var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: IslandView(model: model))
        position(); panel.orderFrontRegardless()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.title = ""
        status.button?.image = BrandIcon.menuBarImage()
        status.button?.imagePosition = .imageOnly
        status.button?.toolTip = "Codex Island · 额度监控"
        status.button?.setAccessibilityLabel("Codex Island 额度监控菜单")
        let menu = NSMenu()
        for (title, action) in [("显示 / 隐藏", #selector(toggle)), ("恢复顶部居中", #selector(recenter)), ("登录授权…", #selector(login)), ("刷新额度", #selector(refresh)), ("退出本应用账号…", #selector(logout)), ("退出", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        let themes = NSMenu()
        themes.delegate = self
        for theme in IslandTheme.allCases {
            let item = NSMenuItem(title: theme.rawValue, action: #selector(changeTheme(_:)), keyEquivalent: "")
            item.target = self
            item.state = theme == model.theme ? .on : .off
            themes.addItem(item)
        }
        let themeItem = NSMenuItem(title: "主题颜色", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.insertItem(themeItem, at: 2)
        status.menu = menu
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.position() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.model.refresh() } })
        model.start()
    }
    func position() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let width: CGFloat = 330
        let height: CGFloat = 28
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 4
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if let theme = IslandTheme(rawValue: item.title) { item.state = theme == model.theme ? .on : .off }
        }
    }
    @objc func changeTheme(_ sender: NSMenuItem) {
        guard let theme = IslandTheme(rawValue: sender.title) else { return }
        model.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func recenter() { position(); panel.orderFrontRegardless() }
    @objc func refresh() { Task { await model.refresh() } }
    @objc func login() { model.login(); position(); panel.orderFrontRegardless() }
    @objc func logout() {
        let alert = NSAlert()
        alert.messageText = "退出 Codex Island 账号？"
        alert.informativeText = "将删除本应用登录文件，不影响其他 Codex 客户端。"
        alert.addButton(withTitle: "退出账号"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { model.logout() }
    }
    @objc func quit() { NSApp.terminate(nil) }
}

@main struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { Text("通过菜单栏 Codex 管理浮窗与登录授权。").padding(24) } }
}
