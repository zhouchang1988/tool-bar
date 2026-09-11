import AppKit
import SwiftUI
import ToolBarCore

// MARK: - 视图模型

final class PopupModel: ObservableObject {
    enum State: Equatable {
        case input
        case result(CommandOutput)
        case error(String)
    }

    @Published var state: State = .input
    @Published var input: String = ""

    var onSubmit: (String) -> Void = { _ in }
}

// MARK: - SwiftUI 视图

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 输入框常驻，不随状态切换消失
            TextField("t / l / db / ip / en / de / u / j", text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 22, design: .monospaced))
                .focused($inputFocused)
                .onSubmit { model.onSubmit(model.input) }

            // 回车后在输入框下方下拉展开结果 / 错误
            switch model.state {
            case .input:
                EmptyView()

            case .result(let output):
                Divider()
                ScrollView(.vertical) {
                    Text(output.display)
                        .font(.system(
                            size: output.isMultiline ? 13 : 20,
                            design: output.isMultiline ? .monospaced : .default
                        ))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                Text("Copied ✓")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

            case .error(let message):
                Divider()
                Text(message)
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 560)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
        )
        .onAppear { focusInput() }
        .onChange(of: model.state) { _ in focusInput() }
    }

    private func focusInput() {
        DispatchQueue.main.async {
            inputFocused = true
        }
    }
}

// MARK: - 浮层窗口（技术方案 3.4）

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    private enum Metrics {
        static let width: CGFloat = 600
        static let inputHeight: CGFloat = 88
        static let errorHeight: CGFloat = 148
        static let resultHeight: CGFloat = 200
        static let multilineHeight: CGFloat = 420
    }

    private let panel: PopupPanel
    private let model = PopupModel()
    private var escMonitor: Any?

    init() {
        panel = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.inputHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        model.onSubmit = { [weak self] text in
            self?.execute(text)
        }
        panel.contentView = NSHostingView(rootView: PopupView(model: model))

        // Esc 立即关闭（PRD 3.8）
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            self.hide()
            return nil
        }

        // 失焦自动关闭
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    deinit {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.input = ""
        model.state = .input
        resize(height: Metrics.inputHeight, animated: false)
        moveToActiveScreen()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func execute(_ text: String) {
        // 空输入直接忽略，对话框保持打开
        guard let result = CommandEngine.execute(text, context: SettingsStore.shared.context) else {
            return
        }
        switch result {
        case .success(let output):
            // 成功结果才写入剪贴板（PRD 3.8）
            ClipboardService.copy(output.copyable)
            model.state = .result(output)
            resize(height: output.isMultiline ? Metrics.multilineHeight : Metrics.resultHeight)
        case .failure(let error):
            model.state = .error(error.message)
            resize(height: Metrics.errorHeight)
        }
    }

    /// 保持浮层顶边不动，仅调整高度。
    private func resize(height: CGFloat, animated: Bool = true) {
        var frame = panel.frame
        frame.origin.y += frame.size.height - height
        frame.size = NSSize(width: Metrics.width, height: height)
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// 定位到鼠标所在屏幕：水平居中、垂直距顶部约 25%。
    private func moveToActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - visibleFrame.height * 0.25 - size.height
        )
        panel.setFrameOrigin(origin)
    }
}
