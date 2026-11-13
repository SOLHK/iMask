import SwiftUI

struct EngineSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: RefreshSession

    var body: some View {
        Form {
            Section("运行方案") {
                Picker("底层方案", selection: Binding(get: { session.engine.route }, set: session.setRoute)) {
                    Text("VideoCall · 默认").tag(PiPEngineRoute.videoCall)
                    Text("PlayerLayer · 兼容").tag(PiPEngineRoute.playerLayerGenerated)
                }
                .disabled(session.isTransitioning)
                LabeledContent("当前状态", value: session.engine.title)
                LabeledContent("运行时间", value: session.engine.runtime)
            }

            Section {
                Picker("保活模式", selection: Binding(get: { session.engine.policy }, set: session.setPolicy)) {
                    ForEach(KeepAlivePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(session.isTransitioning)
            } header: {
                Text("后台维持")
            } footer: {
                Text(session.engine.policy.detail)
            }

            Section("悬浮窗") {
                LabeledContent("高度", value: String(format: "%.1f pt", session.engine.height))
                Slider(value: Binding(get: { session.engine.height }, set: session.setHeight),
                       in: session.engine.minimumHeight...session.engine.maximumHeight,
                       step: session.engine.route.usesPlayerLayer ? 1 : 0.1,
                       onEditingChanged: { editing in if !editing { session.commitHeight() } })
                    .disabled(session.isTransitioning)
                Button("一键最小化") { session.startAndHide() }
                    .disabled(session.isTransitioning)
                Toggle("记住高度", isOn: option("remember", session.engine.rememberHeight))
                Toggle("文字滚动", isOn: option("scrolling", session.engine.scrolling))
                    .disabled(session.engine.route.usesPlayerLayer || session.engine.clock)
                Toggle("时钟内容", isOn: option("clock", session.engine.clock))
                    .disabled(!session.engine.clockAvailable)
                Toggle("关闭前确认", isOn: option("confirmClose", session.engine.closeConfirmation))
                Toggle("悬浮窗被挤出时通知", isOn: option("stoppedNotification", session.engine.stoppedNotification))
            }

            Section("高级") {
                Toggle("音频极限静默", isOn: option("extremeSilent", session.engine.extremeSilent))
                    .disabled(!session.engine.route.usesPlayerLayer)
                Toggle("内容极限静默", isOn: option("contentExtreme", session.engine.contentExtreme))
                Toggle("快捷指令", isOn: Binding(get: { session.shortcutsEnabled }, set: session.setShortcuts))
                Toggle("详细诊断", isOn: Binding(get: { session.debugEnabled }, set: session.setDebug))
            }
        }
        .navigationTitle("运行方案与保活")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onAppear { session.refresh() }
    }

    private func option(_ key: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { session.setOption(key, $0) })
    }
}
