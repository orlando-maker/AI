import SwiftUI

/// Training progress checklist plus certificates, ratings, and
/// endorsements — editable in place.
struct TrainingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(LogbookStore.self) private var logbook
    @Environment(\.dismiss) private var dismiss

    @State private var newRatingName = ""
    @State private var newMilestoneTitle = ""

    private var profile: PilotProfile { profileStore.profile }

    private var trackedHours: Double { logbook.totalFlightTime / 3600 }
    private var totalHours: Double { profile.priorHours + trackedHours }
    private var hoursToGo: Double { max(0, profile.trainingGoalHours - totalHours) }

    var body: some View {
        Form {
            hoursRingSection
            progressSection
            milestonesSection
            ratingsSection
        }
        .navigationTitle("Training & Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Hours ring (status-style progress toward the certificate)

    private var hoursRingSection: some View {
        Section {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.18), lineWidth: 13)
                    Circle()
                        .trim(from: 0, to: min(1, profile.trainingGoalHours > 0
                                               ? totalHours / profile.trainingGoalHours : 0))
                        .stroke(Theme.proGold,
                                style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", totalHours))
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text("of \(Int(profile.trainingGoalHours)) hours")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 175, height: 175)
                .padding(.top, 6)

                Text(hoursToGo > 0
                     ? String(format: "%.1f hours to go — %.1f tracked here + %.1f before the app", hoursToGo, trackedHours, profile.priorHours)
                     : "Goal reached — go schedule that checkride! 🎉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)

            HStack {
                Text("Goal")
                Spacer()
                TextField("40", value: goalHoursBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("h").foregroundStyle(.secondary)
            }
            HStack {
                Text("Hours before TailTrack")
                Spacer()
                TextField("0", value: priorHoursBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("h").foregroundStyle(.secondary)
            }
        } footer: {
            Text("The ring counts your prior time plus every flight in the TailTrack logbook. 40 hours is the FAA minimum for the private certificate — most pilots need more, and that's normal.")
        }
    }

    private var goalHoursBinding: Binding<Double> {
        Binding(
            get: { profileStore.profile.trainingGoalHours },
            set: { newValue in
                var p = profileStore.profile
                p.trainingGoalHours = max(1, newValue)
                profileStore.profile = p
            }
        )
    }

    private var priorHoursBinding: Binding<Double> {
        Binding(
            get: { profileStore.profile.priorHours },
            set: { newValue in
                var p = profileStore.profile
                p.priorHours = max(0, newValue)
                profileStore.profile = p
            }
        )
    }

    // MARK: - Progress

    private var completedCount: Int { profile.milestones.filter(\.completed).count }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Training progress")
                        .font(.headline)
                    Spacer()
                    Text("\(completedCount) of \(profile.milestones.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: profile.milestones.isEmpty ? 0 :
                                Double(completedCount) / Double(profile.milestones.count))
                    .tint(Theme.proGold)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        Section {
            ForEach(profile.milestones) { milestone in
                Button {
                    toggle(milestone)
                } label: {
                    HStack {
                        Image(systemName: milestone.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(milestone.completed ? .green : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(milestone.title)
                                .strikethrough(milestone.completed, color: .secondary)
                            if let date = milestone.date, milestone.completed {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                var p = profileStore.profile
                p.milestones.remove(atOffsets: offsets)
                profileStore.profile = p
            }
            HStack {
                TextField("Add milestone (e.g. Tailwheel checkout)", text: $newMilestoneTitle)
                Button {
                    let title = newMilestoneTitle.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    var p = profileStore.profile
                    p.milestones.append(TrainingMilestone(title: title))
                    profileStore.profile = p
                    newMilestoneTitle = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Milestones")
        } footer: {
            Text("Tap to check off a step — the date is recorded automatically. Swipe to remove steps that don't apply.")
        }
    }

    private func toggle(_ milestone: TrainingMilestone) {
        var p = profileStore.profile
        guard let idx = p.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        p.milestones[idx].completed.toggle()
        p.milestones[idx].date = p.milestones[idx].completed ? Date() : nil
        profileStore.profile = p
    }

    // MARK: - Ratings

    private var ratingsSection: some View {
        Section {
            ForEach(profile.ratings) { rating in
                HStack {
                    Image(systemName: "rosette")
                        .foregroundStyle(Theme.proGold)
                    Text(rating.name)
                    Spacer()
                    if let date = rating.dateEarned {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                var p = profileStore.profile
                p.ratings.remove(atOffsets: offsets)
                profileStore.profile = p
            }
            HStack {
                TextField("Add rating (e.g. Instrument Airplane)", text: $newRatingName)
                Button {
                    let name = newRatingName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    var p = profileStore.profile
                    p.ratings.append(RatingEntry(name: name, dateEarned: Date()))
                    profileStore.profile = p
                    newRatingName = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newRatingName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Certificates, ratings & endorsements")
        } footer: {
            Text("Type ratings, endorsements, anything you've earned — e.g. \"Private Pilot ASEL\", \"High Performance\", \"Type: CE-525\".")
        }
    }
}
