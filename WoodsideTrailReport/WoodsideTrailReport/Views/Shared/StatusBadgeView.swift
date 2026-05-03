import SwiftUI

struct StatusBadgeView: View {
    let stage: StatusStage

    var body: some View {
        Text(stage.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stage.color.opacity(0.18))
            .foregroundStyle(stage.color)
            .clipShape(Capsule())
    }
}
