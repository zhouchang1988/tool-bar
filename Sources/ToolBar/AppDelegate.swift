import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var popupController: PopupController?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popup = PopupController()
        popupController = popup

        HotKeyService.shared.onHotKey = { [weak popup] in
            popup?.toggle()
        }
        HotKeyService.shared.registerDefault()

        registerLoginItemOnFirstLaunch()
        setupMainMenu()
        setupStatusItem()
    }

    /// 默认开启开机自启（PRD 第 4 节）：首次启动尝试注册登录项。
    /// 注册成功才写入已初始化标记；失败（下次启动）再试，
    /// 避免 swift run 等非 .app 环境空跑后『默认开启』永久失效。
    private func registerLoginItemOnFirstLaunch() {
        // 非 .app 包内运行（如 swift run）register 必然失败，直接跳过
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let key = "launchAtLoginInitialized"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try LoginItemService.setEnabled(true)
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // 失败不标记已初始化，下次启动重试；用户也可在菜单手动开关
        }
    }

    /// LSUIElement 应用没有可见菜单栏，而 TextField 的 ⌘V / ⌘C / ⌘X / ⌘A
    /// 依赖主菜单的 key equivalent 分发；补一个隐藏的 Edit 菜单保证粘贴可用。
    private func setupMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.make()
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open ToolBar (⌃⌥Space)",
            action: #selector(openPopup),
            keyEquivalent: ""
        )
        openItem.target = self
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        launchAtLoginItem = loginItem
        let quitItem = NSMenuItem(
            title: "Quit ToolBar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// 菜单每次打开时同步登录项勾选状态（系统设置里也可改，以系统为准）。
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem?.state = LoginItemService.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItemService.setEnabled(!LoginItemService.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openPopup() {
        popupController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
