import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IMaskWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MaskAttributes.self) { _ in
            Color.black
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityLabel("iMask 黑色模式")
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Color.black
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .accessibilityLabel("iMask 黑色模式")
                }
            } compactLeading: {
                blackTile(width: 9)
                    .accessibilityLabel("iMask 黑色模式")
            } compactTrailing: {
                blackTile(width: 9)
                    .accessibilityHidden(true)
            } minimal: {
                blackTile(width: 16)
                    .accessibilityLabel("iMask 黑色模式")
            }
            .keylineTint(.black)
        }
    }

    // Give the system real, opaque content in each slot, within compact layout constraints.
    private func blackTile(width: CGFloat) -> some View {
        Color.black.frame(width: width, height: 16)
    }
}
