import AppKit
import Carbon

/// 基于 Carbon RegisterEventHotKey 的全局快捷键，零第三方依赖（技术方案 3.5）。
/// 默认 ⌃⌥Space（⌥⌘Space 与系统搜索冲突）。
final class HotKeyService {
    static let shared = HotKeyService()

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func registerDefault() {
        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerProcPtr = { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                service.onHotKey?()
            }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x54424C4B), id: 1) // 'TBLK'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
