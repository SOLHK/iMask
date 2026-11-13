import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @ObservedObject var session: RefreshSession
    @ObservedObject var mask: MaskSession
    @ObservedObject var modes: DisplayModeSession
    @State private var report = ""
    @State private var export: ExportFile?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Toggle("开启日志", isOn: Binding(get: { session.loggingEnabled }, set: { enabled in
                    session.setLogging(enabled)
                    refreshReport()
                }))
                .accessibilityIdentifier("enableLogging")
                Text(session.loggingEnabled ? "正在记录刷新回调、电量变化与运行事件" : "记录与统计已停止，保留已记录数据供导出")
                    .font(.caption).foregroundStyle(.secondary)
            } footer: {
                Text("每次开启开始新一轮统计。关闭后停止采样与累计，保留本轮结果。高刷运行本身仍会消耗电量。")
            }
            Section {
                LabeledContent("当前模式", value: modes.selected.title)
                LabeledContent("画中画状态", value: session.engine.title)
                LabeledContent("悬浮窗", value: session.isMinimized ? "最小化" : "显示")
                LabeledContent("保活模式", value: session.engine.policy.title)
                LabeledContent("黑色灵动岛", value: mask.statusTitle)
                Button("检查当前状态") { refreshReport() }
                    .accessibilityIdentifier("refreshDiagnostics")
                Button("导出诊断日志") {
                    session.refresh()
                    mask.refresh(reason: "export")
                    do {
                        let file = try session.diagnostics.export(snapshot: combinedSnapshot)
                        report = session.diagnostics.report(snapshot: combinedSnapshot)
                        export = ExportFile(url: file)
                    } catch {
                        exportError = "无法生成日志文件。\(error.localizedDescription)"
                    }
                }
                .accessibilityIdentifier("exportDiagnostics")
            } footer: {
                Text("导出当前状态、开启日志期间的刷新采样、电量变化、充电与温度状态、运行时长和事件记录。")
            }

            Section {
                LabeledContent("前台回调采样", value: session.foregroundFPS.map { String(format: "%.1f FPS", $0) } ?? "未采样")
                Text("其他 App 的帧率和 iMask 独占耗电无法直接读取，报告会明确标为不可获取。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("查看完整报告") {
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("diagnosticReport")
                }
            }

            Section("技术来源") {
                Link("GlobalRefresh-PiP · Yoroin", destination: URL(string: "https://github.com/Yoroin/GlobalRefresh-PiP")!)
                Link("PiP · CaiWanFeng", destination: URL(string: "https://github.com/CaiWanFeng/PiP")!)
            }
        }
        .navigationTitle("诊断与日志")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshReport() }
        .sheet(item: $export) { file in
            DiagnosticShareSheet(url: file.url) { completed, error in
                if let error {
                    session.diagnostics.recordError("export.shareFailed", error)
                    exportError = "分享日志失败。\(error.localizedDescription)"
                } else {
                    session.diagnostics.record("export.shareCompleted", "completed=\(completed)")
                }
            }
        }
        .alert("导出日志", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func refreshReport() {
        session.refresh()
        mask.refresh(reason: "diagnostics")
        report = session.diagnostics.report(snapshot: combinedSnapshot)
    }

    private var combinedSnapshot: String {
        "selectedDisplayMode=\(modes.selected.rawValue)\nmodeTransitioning=\(modes.isSwitching)\n"
            + session.diagnosticSnapshot + "\n\n" + mask.diagnosticSnapshot
    }

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }
}

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in completion(completed, error) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
