import ServiceManagement

/// 登录项封装：SMAppService.mainApp（macOS 13+，见 PRD 第 4 节）。
/// 状态以系统为准（用户在系统设置里也能改），不另行持久化。
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册 / 注销登录项。仅在 .app 包内运行有效；
    /// `swift run` 直接跑二进制时 register 会抛错，由调用方兜底。
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
