import SwiftUI

/// Training progress checklist plus certificates, ratings, and
/// endorsements — editable in place.
struct TrainingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    @State private var newRatingName = ""
    @State private var newMilestoneTitle = ""

    private var profile: PilotProfile { profileStore.profile }

    var body: some View {
        Form {
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
