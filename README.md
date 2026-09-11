# ToolBar

macOS 菜单栏常驻的极简效率工具（Spotlight / Raycast 风格）：全局快捷键唤起输入框，执行命令后结果显示约 2 秒并自动复制到剪贴板。需求与规则见 `docs/product-requirements.md`，技术方案见 `docs/technical-design.md`。

## 安装

```bash
Scripts/make-app.sh   # 打包 dist/ToolBar.app 和 dist/ToolBar.dmg
open dist/ToolBar.dmg # 打开镜像，把 ToolBar 拖进 Applications
```

无 Dock 图标，菜单栏图标提供 Open / Launch at Login / Quit。零第三方依赖，需 macOS 13+。产物为 Apple Silicon + Intel 通用二进制。

## 使用

默认全局快捷键 `⌃⌥Space` 唤起 / 关闭浮层；`Enter` 执行，`Esc` 关闭，失焦自动关闭。成功结果自动复制到剪贴板，错误只显示不复制。输入命令名加空格时，若剪贴板内容符合该命令的参数要求，会自动粘贴为参数。首次启动默认注册登录项（开机自启），可在菜单栏 Launch at Login 或系统设置中关闭。

## 命令

| 命令 | 示例 | 输出 |
|---|---|---|
| `t` | `t 1756216800` | `2025-08-26 22:00:00`（跟随系统时区；双向：多种时间字符串格式 → 时间戳） |
| `db` | `db 123456 128` | `table: 40`（剪贴板为 `40`；非数字值按 UTF-8 字节做 CRC32 再取模，如 `db abcdefg 256` → `a6`；值加双引号强制按字符串） |
| `ip` | `ip 12345678` / `ip 10.1.2.3` | `0.188.97.78` / `167838211` |
| `en` / `de` | `en https://a.com/a b` | `https%3A%2F%2Fa.com%2Fa%20b` |
| `u` | `u https://a.com/a?a=b&c=d` | 美化后的多行 JSON（重复参数合并为数组） |
| `j` | `j {"name":"张三"}` | 多行格式化 JSON（汉字不转义） |

### `j` 宽松输入

标准 JSON 可直接美化。从日志或 Python 拷出来的「脏」字符串也能解析，例如：

- `\"` 结构引号、弯引号 `“` `”`（含 `\”`）会归一成普通 `"`
- 这类 `\xHH` UTF-8 字节转义会还原成汉字

仍无法解析时显示 `Invalid JSON`。合法 JSON 里真正的 `\"` 不受影响。

## 开发

```bash
swift test          # 命令逻辑单元测试
swift run ToolBar   # 直接运行（调试）
Scripts/make-app.sh # 重新打包 dist/ToolBar.app 和 dist/ToolBar.dmg
```
