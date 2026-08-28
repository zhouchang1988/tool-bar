这个工具非常适合做成一个**极简的 Spotlight / Raycast 风格菜单栏工具**：不需要后端、不需要联网、不需要账号，核心就是「全局快捷键 → 输入 → 解析 → 结果浮层 → 自动复制」。

我建议技术栈直接选：

> **Swift + SwiftUI + AppKit**

而不是 Tauri/Electron。这个项目足够小，原生 Mac 会更干净。

### 1. 产品形态

常驻后台，不显示主窗口。

按一个全局快捷键，例如：

**⌥ Space**

弹出一个很小的输入框：

```text
┌──────────────────────────────────────┐
│ time 1756216800                     │
└──────────────────────────────────────┘
```

回车后：

```text
2025-08-26 13:20:00
```

结果显示约 **2 秒**，同时自动复制到剪贴板，然后输入框自动消失。

整体体验类似一个「程序员专用计算器」。

---

### 2. 命令设计

| 命令     | 输入                          | 输出                    |
| ------ | --------------------------- | --------------------- |
| `time` | `time 1756216800`           | `2025-08-26 13:20:00` |
| `db`   | `db 123456 128`             | 分表结果                  |
| `ip`   | `ip 12345678`               | `0.188.97.78`         |
| `ip`   | `ip 10.1.2.3`               | `167837187`           |
| `en`   | `en https://a.com/a b`      | URL Encode            |
| `de`   | `de https%3A%2F%2Fa.com`    | URL Decode            |
| `url`  | `url https://a.com/a=b&c=d` | `{"a":"b","c":"d"}`   |
| `json` | `json {"a":"b"}`            | 格式化 JSON              |

其中 `time` 可以直接读取 macOS 当前时区：

```text
默认：Asia/Shanghai
```

也可以设置：

```text
跟随系统
Asia/Shanghai
UTC
America/Los_Angeles
...
```

我建议**默认跟随系统时区**，而不是硬编码北京时间。

---

## 3. `db` 命令需要先定义清楚

这里我理解你的意思是：

```text
db ID 分表数
```

根据分表数计算 ID 对应的分表。

例如：

```text
db 123456 128
```

如果分表数是 `10`、`100` 等十进制数，就按照十进制规则。

如果是 `2^n`，例如：

```text
2
4
8
16
32
64
128
256
...
```

则返回 **16 进制形式**。

这里建议 UI 上最终统一成：

```text
db 123456 128

table: 0x40
```

或者如果你的实际业务规则是「ID % 分表数」，则：

```text
123456 % 128 = 64
```

最终：

```text
0x40
```

**这一块建议在开发前把规则定死**，因为「分表 ID」可能还有其他算法，例如 `id / count`、`id % count`、hash 等。

---

# 4. 推荐架构

非常简单，甚至不需要 MVVM 这种复杂结构。

```text
Mac App
│
├── AppDelegate
│   ├── 注册全局快捷键
│   └── 控制 PopupWindow
│
├── PopupWindow
│   └── SwiftUI InputView
│
├── CommandParser
│   └── 识别 time/db/ip/en/de/url/json
│
├── Commands
│   ├── TimeCommand
│   ├── DbCommand
│   ├── IpCommand
│   ├── UrlEncodeCommand
│   ├── UrlDecodeCommand
│   ├── UrlQueryCommand
│   └── JsonCommand
│
└── Clipboard
    └── NSPasteboard
```

核心逻辑甚至可以做到：

```text
输入字符串
    ↓
CommandParser
    ↓
Command
    ↓
Result
    ↓
复制 Clipboard
    ↓
显示 Overlay
    ↓
2 秒后关闭
```

---

# 5. UI 不要做复杂

我反而建议不要做成普通 Mac App。

做成一个**无边框浮层**：

```text
                    ┌────────────────────────┐
                    │ json {"name":"张三"}  │
                    └────────────────────────┘
```

执行后：

```text
                    ┌────────────────────────┐
                    │                         │
                    │ {                       │
                    │   "name": "张三"        │
                    │ }                       │
                    │                         │
                    │       Copied ✓          │
                    └────────────────────────┘
```

2 秒后消失。

`json` 建议支持多行结果，但普通命令只显示一行。

---

# 6. 全局快捷键

这里不要自己造轮子，建议使用一个非常轻量的 Swift Package：

**HotKey / KeyboardShortcuts 类库**

或者直接使用 Carbon 的：

```text
RegisterEventHotKey
```

如果你希望依赖最少，我甚至建议：

> **直接 AppKit + Carbon 实现**

整个 App 可以做到几乎没有第三方依赖。

快捷键可以设置为：

```text
⌥ Space
```

但要注意和其他软件冲突。

更稳妥可以默认：

```text
⌥⌘Space
```

然后允许用户设置。

---

# 7. Clipboard

直接：

```swift
NSPasteboard.general
```

执行结果：

```text
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(result, forType: .string)
```

所以用户完全不需要再复制。

---

# 8. JSON 特别处理

你的要求：

> 不要转义，正常展示汉字

Swift 原生 `JSONSerialization` 就可以很好处理。

输入：

```json
{"name":"张三","age":18,"items":[1,2,3]}
```

输出：

```json
{
  "name": "张三",
  "age": 18,
  "items": [
    1,
    2,
    3
  ]
}
```

同时复制到剪贴板的也是格式化后的 JSON，而不是：

```text
"{\"name\":\"张三\"}"
```

---

# 9. `url` 建议这样实现

不要自己解析 URL。

Swift：

```text
URLComponents
```

输入：

```text
url https://a.com/a=b&c=d
```

解析：

```json
{
  "a": "b",
  "c": "d"
}
```

同时处理：

```text
https://a.com?a=1&a=2
```

可以考虑输出：

```json
{
  "a": ["1", "2"]
}
```

这样比简单 Dictionary 更完整。

---

# 10. 错误处理也要极简

比如：

```text
time abc
```

直接：

```text
Invalid timestamp
```

比如：

```text
json {"a":
```

显示：

```text
Invalid JSON
```

比如：

```text
xxx abc
```

显示：

```text
Unknown command
```

错误结果同样可以复制吗？

我建议：

> **错误不复制，只显示。**

成功结果才复制。

---

# 11. 设置页面只需要几个东西

第一版甚至可以没有设置页面。

后面加一个菜单栏图标：

```text
MyTool
────────────
Settings...
────────────
Quit
```

Settings：

```text
Global Shortcut
[ ⌥⌘Space ]

Timezone
[ System Default ▼ ]

Default DB Format
[ Auto ▼ ]

Launch at Login
[ ✓ ]
```

就够了。

---

# 12. 项目目录

我会这样设计：

```text
~/Developer/QuickTool
│
├── QuickTool.xcodeproj
│
└── QuickTool
    ├── App
    │   ├── AppDelegate.swift
    │   └── QuickToolApp.swift
    │
    ├── UI
    │   ├── PopupWindow.swift
    │   ├── InputView.swift
    │   └── ResultView.swift
    │
    ├── Commands
    │   ├── CommandParser.swift
    │   ├── TimeCommand.swift
    │   ├── DbCommand.swift
    │   ├── IpCommand.swift
    │   ├── UrlCommand.swift
    │   └── JsonCommand.swift
    │
    └── Services
        ├── ClipboardService.swift
        └── HotKeyService.swift
```

不过如果让 AI Coding 来做，我甚至会进一步压缩：

```text
Sources/
├── App.swift
├── Commands.swift
├── Popup.swift
├── HotKey.swift
└── Clipboard.swift
```

**这个项目没必要过度架构。**

---

# 13. 开发顺序

我建议严格按照这个顺序：

### Phase 1：核心功能

先实现：

```text
time
ip
en
de
url
json
```

全部用单元测试验证。

### Phase 2：Mac UI

实现：

```text
全局快捷键
    ↓
弹出输入框
    ↓
Enter
    ↓
结果
    ↓
Clipboard
    ↓
2 秒关闭
```

### Phase 3：`db`

把你实际使用的分表算法确定下来后再加入。

### Phase 4：体验

增加：

* 快捷键设置
* 开机启动
* 菜单栏图标
* 跟随系统时区
* 最近使用命令
* 错误提示
* 深色/浅色模式

---

## 14. 我最推荐的最终技术方案

| 部分        | 技术                           |
| --------- | ---------------------------- |
| App       | **Swift**                    |
| UI        | **SwiftUI**                  |
| Window    | **AppKit NSPanel**           |
| 全局快捷键     | **Carbon**                   |
| Clipboard | **NSPasteboard**             |
| JSON      | **Foundation**               |
| URL       | **Foundation URLComponents** |
| IP        | Swift 自己实现                   |
| 配置        | **UserDefaults**             |
| 开机启动      | **SMAppService**             |
| 架构        | 极简 MVC/组件化                   |
| 第三方依赖     | **尽量 0**                     |

**我会明确选这个，而不是 Tauri。**

因为你的工具本质上只有：

> **一个输入框 + 7 个纯函数 + 一个浮层 + 剪贴板 + 全局快捷键。**

用 Tauri 虽然也能做，但会引入 WebView、前端工程、Rust/JS 通信等额外复杂度。Swift 原生做出来后，App 很可能就是一个**非常轻量的后台小程序**。

如果用 AI 编程，这个项目甚至可以作为一个很好的 **半天～一天完成的 Mac 原生小工具**：先让 AI 做完整 MVP，再让它针对「快捷键唤起速度、窗口定位、动画、剪贴板、内存占用」逐项优化。

