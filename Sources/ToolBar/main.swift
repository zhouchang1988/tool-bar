import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// 无 Dock 图标（等价于 LSUIElement；打包 .app 时 Info.plist 亦已配置）
application.setActivationPolicy(.accessory)
application.run()
