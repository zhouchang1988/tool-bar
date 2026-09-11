import AppKit

/// 剪贴板封装：仅在命令成功时调用，错误路径绝不触碰（技术方案 3.6）。
enum ClipboardService {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
