import AppKit

/// 剪贴板封装：仅在命令成功时调用，错误路径绝不触碰（技术方案 3.6）。
enum ClipboardService {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// 读取剪贴板中的纯文本；非字符串或无内容时返回 nil。
    static func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
