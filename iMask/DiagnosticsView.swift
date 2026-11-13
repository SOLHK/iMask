import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @ObservedObject var session: RefreshSession
    @State private var report = ""
    @State private var export: ExportFile?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("画中画状态", value: session.phase.title)
                LabeledContent("悬浮窗", value: session.isMinimized ? "最小化" : "显示")
                Button("检查当前状态") { refreshReport() }
                    .accessibilityIdentifier("refreshDiagnostics")
                Button("导出诊断日志") {
                    session.refresh()
                    do {
                        let file = try session.diagnostics.export(snapshot: session.diagnosticSnapshot)
                        report = session.diagnostics.report(snapshot: session.diagnosticSnapshot)
                        export = ExportFile(url: file)
                    } catch {
                        exportError = "无法生成日志文件。\(error.localizedDescription)"
                    }
                }
                .accessibilityIdentifier("exportDiagnostics")
            } footer: {
                Text("导出设备信息、画中画状态、帧率采样和最近 256 条事件。日志保存在本机。")
            }

            Section {
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
        report = session.diagnostics.report(snapshot: session.diagnosticSnapshot)
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
