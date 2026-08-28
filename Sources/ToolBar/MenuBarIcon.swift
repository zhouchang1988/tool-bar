import AppKit

/// 菜单栏图标：胶囊输入框 + 光标，与 Resources/toolbar-menubar-icon.png 同款。
/// 用 NSBezierPath 代码绘制并开启 template 模式，自动适配深色 / 浅色菜单栏，
/// 避免直接贴白底 PNG 出现白斑。
enum MenuBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // 胶囊外框（描边）
            let capsuleRect = rect.insetBy(dx: 1.0, dy: 5.0)
            let capsule = NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: capsuleRect.height / 2,
                yRadius: capsuleRect.height / 2
            )
            capsule.lineWidth = 1.8
            capsule.stroke()

            // 光标竖条（填充）
            let caretRect = NSRect(x: 5.4, y: 7.2, width: 1.6, height: 5.6)
            NSBezierPath(roundedRect: caretRect, xRadius: 0.8, yRadius: 0.8).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
