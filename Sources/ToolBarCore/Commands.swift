import Foundation

// MARK: - 错误定义（文案见 PRD 3.8）

public enum CommandError: Error, Equatable {
    case invalidTimestamp
    case invalidIP
    case invalidDbArguments
    case invalidEncodedString
    case invalidURL
    case invalidJSON
    case unknownCommand

    public var message: String {
        switch self {
        case .invalidTimestamp: return "Invalid timestamp"
        case .invalidIP: return "Invalid IP"
        case .invalidDbArguments: return "Invalid db arguments"
        case .invalidEncodedString: return "Invalid encoded string"
        case .invalidURL: return "Invalid URL"
        case .invalidJSON: return "Invalid JSON"
        case .unknownCommand: return "Unknown command"
        }
    }
}

// MARK: - 上下文与输出

public enum DBFormat: String {
    case auto
    case hex
    case decimal
}

public struct CommandContext {
    public var timeZone: TimeZone
    public var dbFormat: DBFormat

    public init(timeZone: TimeZone = .current, dbFormat: DBFormat = .auto) {
        self.timeZone = timeZone
        self.dbFormat = dbFormat
    }
}

/// 命令执行结果。`display` 用于浮层展示，`copyable` 写入剪贴板
/// （如 `db` 展示 `table: 0x40`，剪贴板只写 `0x40`，见 PRD 3.4）。
public struct CommandOutput: Equatable {
    public let display: String
    public let copyable: String
    public let isMultiline: Bool

    public init(display: String, copyable: String? = nil, isMultiline: Bool = false) {
        self.display = display
        self.copyable = copyable ?? display
        self.isMultiline = isMultiline
    }
}

// MARK: - 解析 + 执行入口

public enum CommandEngine {

    /// 返回 nil 表示输入为空（不展示任何结果）。
    public static func execute(
        _ input: String,
        context: CommandContext = CommandContext()
    ) -> Result<CommandOutput, CommandError>? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 只按第一个空格切分，剩余部分原样保留（j 参数内含空格，见技术方案 3.1）
        let name: String
        let rawArgument: String
        if let spaceIndex = trimmed.firstIndex(of: " ") {
            name = String(trimmed[trimmed.startIndex..<spaceIndex])
            rawArgument = String(trimmed[trimmed.index(after: spaceIndex)...])
        } else {
            name = trimmed
            rawArgument = ""
        }
        let argument = rawArgument.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "t": return runTime(argument, context: context)
        case "l": return runLength(argument)
        case "db": return runDb(argument, context: context)
        case "ip": return runIp(argument)
        case "en": return runUrlEncode(argument)
        case "de": return runUrlDecode(argument)
        case "u": return runUrlQuery(argument)
        case "j": return runJson(argument)
        default: return .failure(.unknownCommand)
        }
    }

    /// 全部已知命令名。
    public static let commandNames: Set<String> = ["t", "l", "db", "ip", "en", "de", "u", "j"]

    /// 校验剪贴板内容是否适合作为某命令的参数（用于输入命令 + 空格时自动粘贴）。
    /// 判据与执行一致：以该内容作为参数执行成功即视为合适；Core 无副作用，可安全调用。
    public static func clipboardFits(
        command: String,
        clipboard: String,
        context: CommandContext = CommandContext()
    ) -> Bool {
        let trimmed = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, commandNames.contains(command) else { return false }
        guard let result = execute("\(command) \(trimmed)", context: context) else { return false }
        if case .success = result { return true }
        return false
    }

    // MARK: t —— 双向转换（PRD 3.2）：
    // 整数 → 时间字符串（yyyy-MM-dd HH:mm:ss）；时间字符串 → 秒级 Unix 时间戳。
    // 时间字符串支持多种常见格式（列表逐个尝试），兜底用 NSDataDetector 识别自然语言日期。
    // 时区均走 settings（默认跟随系统）。

    private static let timeStringFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd",
    ]

    private static func runTime(_ argument: String, context: CommandContext) -> Result<CommandOutput, CommandError> {
        // 空参数（直接回车）→ 当前秒级时间戳
        if argument.isEmpty {
            return .success(CommandOutput(display: String(Int64(Date().timeIntervalSince1970))))
        }

        // 整数 → 时间字符串（保持单一输出格式）
        if let timestamp = Int64(argument) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = context.timeZone
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            return .success(CommandOutput(display: formatter.string(from: date)))
        }

        // 时间字符串 → 秒级时间戳：常见格式逐个尝试
        for format in timeStringFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = context.timeZone
            formatter.isLenient = false
            if let date = formatter.date(from: argument) {
                return .success(CommandOutput(display: String(Int64(date.timeIntervalSince1970))))
            }
        }

        // 兜底：NSDataDetector 识别自然语言日期（要求整串匹配，避免误解析）
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let fullRange = NSRange(argument.startIndex..., in: argument)
            if let match = detector.firstMatch(in: argument, range: fullRange),
               match.range == fullRange,
               let date = match.date {
                return .success(CommandOutput(display: String(Int64(date.timeIntervalSince1970))))
            }
        }

        return .failure(.invalidTimestamp)
    }

    // MARK: l —— 字符串长度：按 Character（字形簇）计数，中文每字算 1

    private static func runLength(_ argument: String) -> Result<CommandOutput, CommandError> {
        .success(CommandOutput(display: String(argument.count)))
    }

    // MARK: db —— ID % 分表数；2 的幂输出十六进制，其余十进制（PRD 3.4）

    private static func runDb(_ argument: String, context: CommandContext) -> Result<CommandOutput, CommandError> {
        let parts = argument.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              let id = Int64(parts[0]),
              let count = Int64(parts[1]),
              count > 0 else {
            return .failure(.invalidDbArguments)
        }
        let value = id % count
        let isPowerOfTwo = (count & (count - 1)) == 0
        let formatted: String
        switch context.dbFormat {
        case .auto:
            formatted = isPowerOfTwo ? shardHexString(value, count: count) : String(value)
        case .hex:
            formatted = shardHexString(value, count: count)
        case .decimal:
            formatted = String(value)
        }
        return .success(CommandOutput(display: "table: \(formatted)", copyable: formatted))
    }

    /// 分表十六进制格式：小写、无 `0x` 前缀，按 `count - 1` 的十六进制位数左侧补 0。
    /// 分表 16 → 1 位（`0`–`f`）；64 / 128 / 256 → 2 位（`00`–`ff`）。
    private static func shardHexString(_ value: Int64, count: Int64) -> String {
        let digits = String(count - 1, radix: 16).count
        let raw = String(value, radix: 16)
        return String(repeating: "0", count: max(0, digits - raw.count)) + raw
    }

    // MARK: ip —— 整数 ↔ 点分 IPv4，大端序（PRD 3.3）

    private static func runIp(_ argument: String) -> Result<CommandOutput, CommandError> {
        guard !argument.isEmpty else { return .failure(.invalidIP) }

        if argument.allSatisfy({ $0.isNumber }) {
            guard let value = UInt32(argument) else { return .failure(.invalidIP) }
            let a = value >> 24
            let b = (value >> 16) & 0xFF
            let c = (value >> 8) & 0xFF
            let d = value & 0xFF
            return .success(CommandOutput(display: "\(a).\(b).\(c).\(d)"))
        }

        let parts = argument.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return .failure(.invalidIP) }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let octet = UInt32(part), octet <= 255 else {
                return .failure(.invalidIP)
            }
            value = (value << 8) | octet
        }
        return .success(CommandOutput(display: String(value)))
    }

    // MARK: en / de —— RFC 3986 unreserved 之外全部编码（PRD 3.5）

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func runUrlEncode(_ argument: String) -> Result<CommandOutput, CommandError> {
        guard !argument.isEmpty,
              let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) else {
            return .failure(.invalidEncodedString)
        }
        return .success(CommandOutput(display: encoded))
    }

    private static func runUrlDecode(_ argument: String) -> Result<CommandOutput, CommandError> {
        guard !argument.isEmpty,
              let decoded = argument.removingPercentEncoding else {
            return .failure(.invalidEncodedString)
        }
        return .success(CommandOutput(display: decoded))
    }

    // MARK: u —— URLComponents 解析 query，重复参数合并为数组，输出美化 JSON（PRD 3.6）

    private static func runUrlQuery(_ argument: String) -> Result<CommandOutput, CommandError> {
        guard let components = URLComponents(string: argument),
              let items = components.queryItems, !items.isEmpty else {
            return .failure(.invalidURL)
        }
        var grouped: [String: [String]] = [:]
        for item in items {
            grouped[item.name, default: []].append(item.value ?? "")
        }
        var object: [String: Any] = [:]
        for (key, values) in grouped {
            object[key] = values.count == 1 ? values[0] : values
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let json = String(data: data, encoding: .utf8) else {
            return .failure(.invalidURL)
        }
        return .success(CommandOutput(display: json, isMultiline: true))
    }

    // MARK: j —— 2 空格缩进美化，不转义非 ASCII（PRD 3.7）

    private static func runJson(_ argument: String) -> Result<CommandOutput, CommandError> {
        // 优先严格解析；失败再按日志/Python 风格转义做宽松兜底
        if let output = prettyPrintedJSON(from: argument) {
            return .success(output)
        }
        let relaxed = normalizeJSONQuotes(decodingHexByteEscapes(argument))
        if relaxed != argument, let output = prettyPrintedJSON(from: relaxed) {
            return .success(output)
        }
        return .failure(.invalidJSON)
    }

    private static func prettyPrintedJSON(from string: String) -> CommandOutput? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return CommandOutput(display: result, isMultiline: true)
    }

    /// 将连续的 `\xHH` 序列按 UTF-8 字节解码为字符（如 `\xe7\xaa\xa6` → 窦）。
    /// 无法整体解码的字节段保留原样。
    private static func decodingHexByteEscapes(_ s: String) -> String {
        let chars = Array(s)
        var result = ""
        var bytes: [UInt8] = []
        var i = 0

        func flushBytes() {
            guard !bytes.isEmpty else { return }
            if let decoded = String(bytes: bytes, encoding: .utf8) {
                result += decoded
            } else {
                result += bytes.map { String(format: "\\x%02x", $0) }.joined()
            }
            bytes.removeAll()
        }

        while i < chars.count {
            if chars[i] == "\\", i + 3 < chars.count, chars[i + 1] == "x",
               let byte = UInt8(String(chars[i + 2 ... i + 3]), radix: 16) {
                bytes.append(byte)
                i += 4
            } else {
                flushBytes()
                result.append(chars[i])
                i += 1
            }
        }
        flushBytes()
        return result
    }

    /// 统一引号：`\”`/`\“`（反斜杠 + 弯引号）与 `\"` → ASCII `"`；残留弯引号也归一。
    private static func normalizeJSONQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\u{201D}", with: "\"")
            .replacingOccurrences(of: "\\\u{201C}", with: "\"")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }
}
