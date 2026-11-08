import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PapAIWidgets: WidgetBundle {
    var body: some Widget { HelpLiveActivity() }
}

/// L'alerte de l'écran verrouillé et de la Dynamic Island.
struct HelpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HelpActivityAttributes.self) { ctx in
            LockScreenCard(s: ctx.state)
                .activityBackgroundTint(ctx.state.urgent ? PapColors.ink : PapColors.card)
                .activitySystemActionForegroundColor(ctx.state.urgent ? .white : PapColors.ink)
                .widgetURL(URL(string: "papai://open"))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("Mascot").resizable().scaledToFit()
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.since, style: .relative)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.headline).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.subline).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                        if let cta = s.cta {
                            Text(cta).font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(PapColors.primary, in: Capsule())
                        } else if s.phase == .working || s.phase == .paused {
                            Bar(value: s.progress, track: .white.opacity(0.15), fill: PapColors.accentBright)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            } compactLeading: {
                Image("Mascot").resizable().scaledToFit().frame(width: 22, height: 22)
                    .clipShape(Circle())
            } compactTrailing: {
                Text(s.short).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(s.urgent ? PapColors.accentBright : .white)
                    .lineLimit(1)
            } minimal: {
                Circle().fill(s.urgent ? PapColors.accentBright : .white.opacity(0.5))
                    .frame(width: 10, height: 10)
            }
            .widgetURL(URL(string: "papai://open"))
            .keylineTint(PapColors.accentBright)
        }
    }
}

