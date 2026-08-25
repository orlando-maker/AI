import SwiftUI

/// Badge wall: milestones unlocked from the logbook, mirrored to Game
/// Center when connected.
struct AchievementsView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(\.dismiss) private var dismiss

    @State private var gameCenter = GameCenterManager()

    private var flights: [Flight] { logbook.flights }
    private var unlockedIDs: Set<String> { Set(AchievementCatalog.unlockedIDs(for: flights)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                grid
                gameCenterCard
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onChange(of: gameCenter.isAuthenticated) { _, authenticated in
            if authenticated {
                gameCenter.report(unlockedIDs: Array(unlockedIDs))
            }
        }
        .onAppear {
            if gameCenter.isAuthenticated {
                gameCenter.report(unlockedIDs: Array(unlockedIDs))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("\(unlockedIDs.count) of \(AchievementCatalog.all.count)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("badges earned")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                  spacing: 16) {
            ForEach(AchievementCatalog.all) { achievement in
                let unlocked = unlockedIDs.contains(achievement.id)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(unlocked ? Theme.proGold.opacity(0.18) : Color.gray.opacity(0.12))
                        Image(systemName: unlocked ? achievement.icon : "lock.fill")
                            .font(.title2)
                            .foregroundStyle(unlocked ? Theme.proGold : Color.secondary)
                    }
                    .frame(width: 62, height: 62)
                    .overlay(
                        Circle().strokeBorder(unlocked ? Theme.proGold : Color.clear, lineWidth: 1.5)
                    )
                    Text(achievement.title)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(achievement.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(unlocked ? 1 : 0.75)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var gameCenterCard: some View {
        VStack(spacing: 10) {
            if gameCenter.isAuthenticated {
                Label(gameCenter.statusMessage ?? "Connected to Game Center",
                      systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Button {
                    gameCenter.authenticate()
                } label: {
                    Label("Connect Game Center", systemImage: "gamecontroller.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                if let status = gameCenter.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Optional — badges work without it. Connecting mirrors them to Game Center so they show on your Apple Games profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
