import SwiftUI

// UPS/FedEx-style vertical status timeline.
// Always shows all 6 stages. Completed ones are filled; future ones are grayed.
struct ReportStatusTimelineView: View {
    let entries: [StatusHistoryEntry]
    let currentStage: StatusStage

    private let allStages = StatusStage.allCases

    private func entry(for stage: StatusStage) -> StatusHistoryEntry? {
        entries.first { $0.statusStage == stage }
    }

    private func isCompleted(_ stage: StatusStage) -> Bool {
        let completedRaw = entries.map { $0.stage }
        return completedRaw.contains(stage.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(allStages.enumerated()), id: \.element) { idx, stage in
                HStack(alignment: .top, spacing: 12) {
                    // Circle + connector line
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(isCompleted(stage) ? stage.color : Color(.systemGray4))
                                .frame(width: 28, height: 28)
                            Image(systemName: stage.sfSymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        if idx < allStages.count - 1 {
                            Rectangle()
                                .fill(isCompleted(allStages[idx + 1])
                                      ? allStages[idx + 1].color.opacity(0.4)
                                      : Color(.systemGray5))
                                .frame(width: 2, height: 36)
                        }
                    }

                    // Text content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stage.label)
                            .font(.subheadline)
                            .fontWeight(isCompleted(stage) ? .semibold : .regular)
                            .foregroundStyle(isCompleted(stage) ? .primary : .secondary)

                        if let e = entry(for: stage) {
                            Text(e.updatedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let notes = e.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 1)
                            }
                        } else {
                            Text(stage.sublabel)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.bottom, idx < allStages.count - 1 ? 36 : 8)
                }
                .padding(.top, idx == 0 ? 8 : 0)
            }
        }
        .padding(.horizontal, 4)
    }
}
