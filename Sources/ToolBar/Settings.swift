import Foundation
import ToolBarCore

/// UserDefaults 配置封装（技术方案 3.8）。设置页面属 Phase 4，当前仅提供默认值。
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let timeZoneIdentifier = "timeZoneIdentifier" // "system" 表示跟随系统
        static let dbFormat = "dbFormat"                     // "auto" | "hex" | "decimal"
    }

    var timeZone: TimeZone {
        get {
            guard let identifier = defaults.string(forKey: Key.timeZoneIdentifier),
                  identifier != "system",
                  let timeZone = TimeZone(identifier: identifier) else {
                return .current
            }
            return timeZone
        }
        set {
            defaults.set(newValue.identifier, forKey: Key.timeZoneIdentifier)
        }
    }

    var dbFormat: DBFormat {
        get {
            DBFormat(rawValue: defaults.string(forKey: Key.dbFormat) ?? DBFormat.auto.rawValue) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.dbFormat)
        }
    }

    var context: CommandContext {
        CommandContext(timeZone: timeZone, dbFormat: dbFormat)
    }

    private init() {}
}
