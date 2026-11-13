import SwiftUI

struct ContentView: View {
    @ObservedObject var session: RefreshSession
    @ObservedObject var mask: MaskSession
    @ObservedObject var modes: DisplayModeSession
    @State private var showsEngineSettings = false

    private var busy: Bool { modes.isSwitching || session.isTransitioning || mask.isBusy }
    private var running: Bool { modes.selected == .island ? mask.status.isRunning : session.isRunning }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("功能", selection: Binding(get: { modes.selected }, set: modes.select)) {
                        ForEach(DisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(busy)
                    .accessibilityIdentifier("displayMode")

                    if modes.selected == .floatingWindow {
                        floatingWindowHeader
                        RefreshPreview(session: session)
                            .frame(maxWidth: 300)
                            .frame(height: 100)
                            .clipped()
                    } else {
                        islandHeader
                    }

                    HStack(spacing: 8) {
                        if busy {
                            ProgressView()
                            Text("正在切换状态")
                        } else {
                            Image(systemName: running ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(running ? Color.blue : Color.secondary)
                            Text(modes.selected == .island ? mask.statusTitle : session.engine.title)
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("modeStatus")

                    Button { modes.toggle() } label: {
                        Label((running ? "关闭" : "开启") + modes.selected.title,
                              systemImage: running ? "stop.fill" : "power")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(busy || (modes.selected == .island && !mask.isEnabled && !running))
                    .accessibilityIdentifier("toggleMode")

                    if let error = modes.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if modes.selected == .floatingWindow {
                        Button("开启并隐藏悬浮窗") { modes.startHiddenWindow() }
                            .disabled(busy)
                        floatingWindowSettings
                    } else {
                        Text(mask.isEnabled ? (running ? "已启动，返回桌面查看灵动岛" : "标准长度 · 纯黑显示") : "请在系统设置中允许 iMask 实时活动")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        DiagnosticsView(session: session, mask: mask, modes: modes)
                    } label: {
                        HStack {
                            Label("诊断与日志", systemImage: "waveform.path.ecg")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6).padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("openDiagnostics")
                }
                .padding(24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("iMask")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.blue)
            .sheet(isPresented: $showsEngineSettings) {
                NavigationStack { EngineSettingsView(session: session) }
            }
        }
    }

    private var floatingWindowHeader: some View {
        VStack(spacing: 12) {
            Text("悬浮窗高刷").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("120").font(.system(size: 88, weight: .light, design: .rounded)).tracking(-4)
                Text("Hz").font(.title2.weight(.medium)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("目标刷新率 120 赫兹")
            Text("目标刷新率").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 12)
    }

    private var islandHeader: some View {
        VStack(spacing: 24) {
            Text("黑色灵动岛").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            Capsule().fill(.black).frame(width: 134, height: 36)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("标准长度示意")
            Text("标准长度示意").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var floatingWindowSettings: some View {
        VStack(spacing: 18) {
            HStack {
                Text("悬浮窗").font(.headline)
                Spacer()
                Picker("悬浮窗", selection: Binding(get: { session.isMinimized }, set: session.setMinimized)) {
                    Text("最小化").tag(true)
                    Text("显示").tag(false)
                }
                .pickerStyle(.segmented).frame(maxWidth: 200).disabled(busy)
                .accessibilityIdentifier("windowMode")
            }
            Divider()
            Button { showsEngineSettings = true } label: {
                HStack {
                    Text("运行方案与保活")
                    Spacer()
                    Text(session.engine.route.usesPlayerLayer ? "PlayerLayer" : "VideoCall").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .disabled(busy)
            Text(session.engine.policy.title).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("屏幕上限").font(.caption).foregroundStyle(.secondary)
                    Text("\(session.screenMaximum) Hz").font(.title3.weight(.semibold)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("本页帧率").font(.caption).foregroundStyle(.secondary)
                    Text(session.loggingEnabled ? (session.foregroundFPS.map { String(format: "%.0f FPS", $0) } ?? "—") : "未采样")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding(22)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
