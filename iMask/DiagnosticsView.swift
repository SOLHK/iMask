import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @ObservedObject var session: MaskSession
    @State private var report = ""
    @State private var export: ExportFile?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("实时活动权限", value: session.isEnabled ? "已允许" : "不可用")
                LabeledContent("宽度设置", value: session.selectedWidth.title)
                Button("检查当前状态") { refreshReport() }
                    .accessibilityIdentifier("refreshDiagnostics")
                Button("导出诊断日志") {
                    session.refresh(reason: "export")
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
                Text("导出文本包含设备类型、系统版本、显示参数、宽度设置和最近 256 条事件。可通过分享菜单发送或存到“文件”。")
            }

            Section {
                DisclosureGroup("查看完整报告") {
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("diagnosticReport")
                }
            } footer: {
                Text("日志保存在本机，重启 App 后保留。系统未提供灵动岛实际像素尺寸和当前可见性的查询接口。")
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
        session.refresh(reason: "diagnostics")
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
