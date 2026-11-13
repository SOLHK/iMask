import SwiftUI

struct ContentView: View {
    @ObservedObject var session: RefreshSession
    @ObservedObject var mask: MaskSession
    @State private var showsEngineSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Text("高刷新率")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("120")
                                .font(.system(size: 112, weight: .light, design: .rounded))
                                .tracking(-5)
                            Text("Hz")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("目标刷新率 120 赫兹")

                        Text("目标刷新率")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        RefreshPreview(session: session)
                            .frame(maxWidth: 300)
                            .frame(height: 120)
                            .padding(.vertical, 16)

                        HStack(spacing: 8) {
                            Image(systemName: session.isRunning ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(session.isRunning ? Color.blue : Color.secondary)
                            Text(session.engine.suspended ? "画中画已暂停" : session.engine.title)
                        }
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("refreshStatus")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    Button {
                        if session.canStop { session.stop() } else { session.start() }
                    } label: {
                        Label(session.canStop ? "停止高刷" : "开启高刷",
                              systemImage: session.canStop ? "stop.fill" : "power")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(session.isTransitioning)
                    .accessibilityIdentifier("toggleRefresh")

                    Button("开启并隐藏悬浮窗") { session.startAndHide() }
                        .disabled(session.isTransitioning)

                    VStack(spacing: 18) {
                        HStack {
                            Text("悬浮窗").font(.headline)
                            Spacer()
                            Picker("悬浮窗", selection: Binding(
                                get: { session.isMinimized },
                                set: { session.setMinimized($0) }
                            )) {
                                Text("最小化").tag(true)
                                Text("显示").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                            .disabled(session.isTransitioning)
                            .accessibilityIdentifier("windowMode")
                        }
                        Divider()
                        Button { showsEngineSettings = true } label: {
                            HStack {
                                Text("运行方案与保活")
                                Spacer()
                                Text(session.engine.route.usesPlayerLayer ? "PlayerLayer" : "VideoCall")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.primary)
                        }
                        Text(session.engine.policy.title)
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("屏幕上限").font(.caption).foregroundStyle(.secondary)
                                Text("\(session.screenMaximum) Hz")
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("本页帧率").font(.caption).foregroundStyle(.secondary)
                                Text(session.foregroundFPS.map { String(format: "%.0f FPS", $0) } ?? "—")
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                    .padding(22)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { mask.status.isRunning },
                            set: { enabled in
                                if enabled { mask.start() } else { Task { await mask.stop() } }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("黑色灵动岛").font(.headline)
                                Text("标准长度").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(mask.isBusy || (!mask.isEnabled && !mask.status.isRunning))
                        .accessibilityIdentifier("toggleIsland")
                        Text(mask.isEnabled ? mask.statusTitle : "请在系统设置中允许 iMask 实时活动")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = mask.errorMessage {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(22)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))

                    NavigationLink {
                        DiagnosticsView(session: session, mask: mask)
                    } label: {
                        HStack {
                            Label("诊断与日志", systemImage: "waveform.path.ecg")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("openDiagnostics")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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
}
