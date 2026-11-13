import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var session: MaskSession
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Capsule()
                        .fill(.black)
                        .frame(width: session.status.isRunning ? 136 : 96, height: 34)
                        .frame(maxWidth: .infinity, minHeight: 102)
                        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                } header: {
                    Text("效果预览")
                } footer: {
                    Text("示意图。实际宽度、高度和圆角由 iOS 决定。")
                }

                Section {
                    LabeledContent {
                        Text(statusTitle)
                    } label: {
                        Text("实时活动")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("实时活动")
                    .accessibilityValue(Text(statusTitle))
                    .accessibilityIdentifier("maskStatus")

                    if session.status.isRunning {
                        Button("关闭黑色模式", role: .destructive) {
                            Task { await session.stop() }
                        }
                        .disabled(session.isStopping)
                        .accessibilityIdentifier("stopMask")
                    } else {
                        Button("开启黑色模式") { session.start() }
                            .disabled(!session.isEnabled)
                            .accessibilityIdentifier("startMask")
                    }

                    if !session.isEnabled, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("打开系统设置") { openURL(url) }
                    }
                } footer: {
                    Text(session.errorMessage ?? statusDetail)
                }

                Section("显示限制") {
                    Text("在配备灵动岛的 iPhone 上，桌面和其他 App 可显示黑色实时活动。其他活动、系统提示和显示环境会影响它是否出现。")
                    Text("每次最多持续 8 小时。系统结束后，可以回到 iMask 重新开启。锁屏可能显示对应的黑色卡片。")
                    Text("轻点灵动岛中的 iMask 活动会打开本 App，长按会展开，均由 iOS 处理。")
                }
                .font(.subheadline)
            }
            .navigationTitle("iMask")
        }
    }

    private var statusTitle: String {
        if session.isStopping { return "正在关闭" }
        switch session.status {
        case .off: return session.isEnabled ? "未开启" : "不可用"
        case .running: return "运行中"
        case .stopped: return "已关闭"
        case .ended: return "活动已结束"
        }
    }

    private var statusDetail: String {
        if !session.isEnabled && !session.status.isRunning {
            return session.status == .ended
                ? "上次活动已结束。请在系统设置中允许实时活动后再开启。"
                : "请检查系统设置中是否允许 iMask 使用实时活动。"
        }

        switch session.status {
        case .off:
            return "开启后可返回桌面，查看 iOS 如何显示活动。"
        case .running(let startedAt):
            let limit = startedAt.addingTimeInterval(8 * 60 * 60)
                .formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
            return "本次最长可运行至\(limit)。运行状态由 ActivityKit 提供，实际是否显示由 iOS 决定。"
        case .stopped:
            return "已手动关闭本次实时活动。"
        case .ended:
            return "上次活动已结束或被移除。可以再次开启。"
        }
    }
}
