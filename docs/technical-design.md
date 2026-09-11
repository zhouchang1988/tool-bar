# ToolBar 技术方案

配套文档：`docs/product-requirements.md`（功能规则以 PRD 为准）。

## 1. 技术选型

| 部分 | 技术 | 备注 |
|---|---|---|
| 语言 / App | Swift | macOS 13+ |
| UI | SwiftUI | 输入框与结果视图 |
| 浮层窗口 | AppKit `NSPanel` | 无边框、可成为 key window |
| 全局快捷键 | Carbon `RegisterEventHotKey` | 零第三方依赖，不引 HotKey 类库 |
| 剪贴板 | `NSPasteboard.general` | |
| JSON | Foundation `JSONSerialization` | |
| URL | Foundation `URLComponents` | |
| IP 转换 | 手写纯函数 | |
| 配置存储 | `UserDefaults` | |
| 开机启动 | `SMAppService`（macOS 13+） | |
| 架构 | 极简组件化，不上 MVVM | |
| 第三方依赖 | **0** | |

不选 Tauri / Electron 的理由：整个 App 本质是「一个输入框 + 7 个纯函数 + 一个浮层 + 剪贴板 + 全局快捷键」，原生方案避免 WebView、前端工程与跨语言通信的复杂度。

## 2. 总体架构

```text
Mac App（LSUIElement = true，无 Dock 图标）
│
├── AppDelegate
│   ├── HotKeyService      注册全局快捷键
│   └── PopupWindowController   控制浮层显隐
│
├── UI（SwiftUI + NSPanel）
│   ├── InputView          命令输入
│   └── ResultView         结果 / 错误展示
│
├── Commands（纯逻辑，可单测）
│   ├── CommandParser      解析输入字符串 → Command
│   ├── TimeCommand
│   ├── DbCommand
│   ├── IpCommand
│   ├── UrlEncodeCommand / UrlDecodeCommand
│   ├── UrlQueryCommand
│   └── JsonCommand
│
└── Services
    ├── ClipboardService   NSPasteboard 封装
    └── SettingsStore      UserDefaults 封装
```

核心数据流（同步、单向）：

```text
输入字符串
    ↓ CommandParser
Command + 参数
    ↓ 执行（纯函数）
Result<String, CommandError>
    ↓ 成功 → ClipboardService 写入 + ResultView 展示
    ↓ 失败 → ResultView 展示（不写剪贴板）
    ↓
约 2 秒 → 关闭浮层
```

## 3. 模块设计

### 3.1 CommandParser

输入首词（空格分隔）匹配命令名，其余整体作为参数：

```swift
enum CommandKind: String {
    case t, db, ip, en, de, u, j
}

struct ParsedCommand {
    let kind: CommandKind
    let argument: String   // 首词之后的原文，不去空格/引号
}

enum ParseResult {
    case command(ParsedCommand)
    case unknown(String)          // → "Unknown command"
    case empty
}
```

注意：`j {"a": "b"}` 这类参数内含空格，所以**只按第一个空格切分**，剩余部分原样保留。

### 3.2 命令执行协议

```swift
protocol ToolCommand {
    func run(argument: String, settings: SettingsStore) -> Result<String, CommandError>
}

enum CommandError: Error {
    case invalidTimestamp
    case invalidIP
    case invalidDbArguments
    case invalidEncodedString
    case invalidURL
    case invalidJSON

    var message: String { ... }  // PRD 3.8 的文案
}
```

所有命令是**无 IO 的纯函数**（除读取 settings 外），Phase 1/3 用单元测试覆盖。

### 3.3 各命令实现要点

**TimeCommand**（双向转换，规则按 PRD 3.2）

```swift
// 整数 → 时间字符串（固定输出 yyyy-MM-dd HH:mm:ss）
if let ts = Int64(arg) {
    return .success(fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts))))
}
// 时间字符串 → 秒级 Unix 时间戳：常见格式列表逐个尝试
// （yyyy-MM-dd HH:mm:ss / HH:mm / 'T'HH:mm:ss / 仅日期 / 斜杠变体），
// DateFormatter 设 en_US_POSIX、isLenient = false，时区走 settings
// 兜底：NSDataDetector 自然语言日期识别（要求整串匹配）
```

**DbCommand**（规则按 PRD 3.4）

```swift
// 值带双引号 → 强制按字符串（引号内允许空格）；否则按空白切出「值 + 分表数」
guard let count = Int64(countString), count > 0 else {
    return .failure(.invalidDbArguments)
}
// 纯数字 → 直接取模；非数字 / 加引号 → 对 UTF-8 字节做标准 CRC-32（zlib）再取模
let value = isNumeric ? id % count : Int64(crc32(valueString)) % count
// count 是 2 的幂：(count & (count - 1)) == 0
let isPowerOfTwo = (count & (count - 1)) == 0
// 2 的幂 → 小写十六进制、无 0x 前缀，按 count-1 的十六进制位数左侧补 0
// （16 → 1 位 0–f；64 / 128 / 256 → 2 位 00–ff），其余按十进制
return .success(isPowerOfTwo ? shardHex(value, count: count)
                             : String(value))
```

展示层加 `table: ` 前缀，剪贴板只写值本身。

**IpCommand**

- 纯数字：`UInt32` → `(v >> 24, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)` 拼点分。
- 点分：split(".") 得 4 段且每段 0...255 → `(a << 24) | (b << 16) | (c << 8) | d`。
- 金标（大端序，已用系统工具核算）：`ip 10.1.2.3` → `0x0A010203` = `167838211`；反向 `ip 167838211` → `10.1.2.3`。另一例 `ip 12345678` → `0x00BC614E` → `0.188.97.78`。实现后以此两组用例做单元测试校准方向。

**UrlEncodeCommand / UrlDecodeCommand**

```swift
// en —— 规则按 PRD 3.5：只保留 RFC 3986 unreserved 字符，
// 不能直接用 .urlQueryAllowed（它放行 ":" "/"，会得到与 PRD 示例不一致的结果）
let unreserved = CharacterSet.alphanumerics
    .union(CharacterSet(charactersIn: "-._~"))
guard let encoded = arg.addingPercentEncoding(withAllowedCharacters: unreserved) else {
    return .failure(.invalidEncodedString)
}
// en https://a.com/a b → https%3A%2F%2Fa.com%2Fa%20b

// de
guard let s = arg.removingPercentEncoding else { return .failure(.invalidEncodedString) }
```

**UrlQueryCommand**

```swift
guard let comps = URLComponents(string: arg), let items = comps.queryItems, !items.isEmpty else {
    return .failure(.invalidURL)
}
// 收集为 [String: [String]]，单值展开为字符串，多值保持数组
// 输出美化 JSON（.prettyPrinted + .sortedKeys + .withoutEscapingSlashes，
// 与 JsonCommand 同一套序列化方式，不转义非 ASCII），结果按多行展示
```

**JsonCommand**

```swift
guard let data = arg.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) else {
    return .failure(.invalidJSON)
}
let out = try JSONSerialization.data(withJSONObject: obj,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
// JSONSerialization 默认不转义非 ASCII 字符，汉字原样输出
```

### 3.4 浮层窗口（NSPanel + SwiftUI）

```swift
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: ...,
                   styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
    }
    override var canBecomeKey: Bool { true }
}
```

- 位置：当前鼠标所在屏幕，水平居中、垂直距顶部约 25%。
- 内容用 `NSHostingView` 承载 SwiftUI 视图（InputView / ResultView 状态切换）。
- `orderFrontRegardless()` + `makeKey()` 唤起；`orderOut(nil)` 关闭。
- 唤起时清空输入框并把焦点交给 TextField（SwiftUI `@FocusState`）。
- LSUIElement 应用无可见菜单栏，TextField 的 ⌘V/⌘C/⌘X/⌘A 依赖主菜单 key equivalent 分发；AppDelegate 启动时需补一个隐藏的 Edit 主菜单，否则输入框无法粘贴。

### 3.5 全局快捷键（Carbon）

不引第三方库，直接用 Carbon：

```swift
// RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), ...)
// 安装 EventHandler 处理 kEventClassKeyboard / kEventHotKeyPressed
```

- 默认键位 `⌃⌥Space`（`kVK_Space` + `controlKey | optionKey`；⌥⌘Space 与系统搜索冲突）。
- 触发热键 → `PopupController.shared.toggle()`（可见则关闭，隐藏则唤起）。
- 自定义快捷键通过录制按键 → 存 UserDefaults → 重新注册（Phase 4）。

### 3.6 剪贴板

```swift
enum ClipboardService {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
```

仅在命令成功时调用；错误路径绝不触碰剪贴板。

### 3.7 结果自动关闭

ResultView 出现后启动 `Timer`（约 2 秒，`RunLoop.main`）→ 关闭浮层并重置状态。Esc 通过本地 `NSEvent` 监听 / SwiftUI `onKeyPress` 立即关闭。

### 3.8 设置存储

```swift
final class SettingsStore {
    // UserDefaults keys:
    // shortcutKeyCode / shortcutModifiers
    // timeZoneIdentifier ("system" 表示跟随系统)
    // dbFormat ("auto" | "hex" | "decimal")
    // launchAtLogin: Bool
}
```

开机启动（Phase 4）：

```swift
try SMAppService.mainApp.register()   // 或 .unregister()
```

## 4. 项目结构

保持扁平，不过度架构：

```text
ToolBar/
├── ToolBar.xcodeproj
├── ToolBar/
│   ├── App.swift            // App 入口 + AppDelegate
│   ├── Commands.swift       // Parser + 全部命令（纯逻辑）
│   ├── Popup.swift          // PopupPanel + InputView + ResultView
│   ├── HotKey.swift         // Carbon 快捷键
│   ├── Clipboard.swift      // ClipboardService
│   └── Settings.swift       // SettingsStore（Phase 4 扩展设置页）
└── ToolBarTests/
    └── CommandsTests.swift  // 全部命令的单元测试
```

Info.plist 关键配置：

```xml
<key>LSUIElement</key><true/>
```

## 5. 测试计划

### 单元测试（Phase 1 / Phase 3 的验收依据）

| 用例 | 断言 |
|---|---|
| `t 1756216800`（固定时区 UTC） | `2025-08-26 14:00:00` |
| `t 1756216800`（固定时区 Asia/Shanghai） | `2025-08-26 22:00:00` |
| `t 2025-08-26 14:00:00`（固定时区 UTC） | `1756216800` |
| `t 2025-08-26 22:00:00`（固定时区 Asia/Shanghai） | `1756216800` |
| `t abc` | `.invalidTimestamp` |
| `db 123456 128` | `40`（64 的十六进制，2 位补零） |
| `db 11 16` | `b`（1 位十六进制） |
| `db 123456 100` | `56`（十进制） |
| `db abcdefg 256` | `a6`（字符串走 CRC32：824863398 % 256 = 166） |
| `db "123456" 256` | `61`（引号强制字符串；不加引号直接取模得 `40`） |
| `ip 10.1.2.3` | `167838211` |
| `ip 167838211` | `10.1.2.3` |
| `en https://a.com/a b` | `https%3A%2F%2Fa.com%2Fa%20b` |
| `de` 非法百分号串 | `.invalidEncodedString` |
| `u https://a.com/?a=1&a=2` | 美化多行 JSON，重复 key 合并为数组 |
| `j {"name":"张三"}` | 多行、含原样汉字 |
| `j {"a":` | `.invalidJSON` |
| `xxx abc` | Unknown command |

时区相关测试显式注入 `TimeZone(identifier: "UTC")`，避免依赖测试机环境。

### 手动验收（Phase 2 / Phase 4）

- 热键唤起 / 再按关闭、Esc 关闭、失焦处理。
- 成功路径剪贴板内容与显示一致（含多行 JSON）。
- 2 秒自动关闭、错误不复制。
- 深色 / 浅色外观、多屏定位、开机启动开关。

## 6. 开发顺序

按 PRD 第 6 节里程碑执行：Phase 1 命令纯逻辑（带单测）→ Phase 2 浮层与快捷键链路 → Phase 3 `db` → Phase 4 设置与体验项。MVP 目标半天～一天完成。
