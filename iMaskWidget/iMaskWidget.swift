import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IMaskWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MaskAttributes.self) { _ in
            Color.clear
                .frame(height: 0)
                .accessibilityLabel("iMask 黑色模式")
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Color.black
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .accessibilityLabel("iMask 黑色模式")
                }
            } compactLeading: {
                blackTile(width: context.state.effectiveWidth.sideWidth)
                    .accessibilityLabel("iMask 黑色模式")
            } compactTrailing: {
                blackTile(width: context.state.effectiveWidth.sideWidth)
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
