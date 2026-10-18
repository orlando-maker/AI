import SwiftUI

/// TailTrack Pro's "Advanced UI customization": accent color and app icon,
/// plus the clock (local or Zulu), which is free for everyone.
struct CustomizeView: View {
    @Environment(ProStore.self) private var pro
    @Bindable private var customization = Customization.shared
    @State private var showingPaywall = false
    @State private var currentIcon: Customization.AppIcon = .paper
    @State private var iconError: String?

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                    ForEach(Customization.Accent.allCases) { accent in
                        Button {
                            choose(accent)
                        } label: {
                            accentSwatch(accent)
                        }
                        .buttonStyle(.pressable)
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Accent color")
            } footer: {
                Text(pro.isPro ? "Buttons, the route line, your airplane on the map, and highlights everywhere."
                               : "Safety Orange is everyone's. The rest come with TailTrack Pro.")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Customization.AppIcon.allCases) { icon in
                            Button {
                                choose(icon)
                            } label: {
                                iconTile(icon)
                            }
                            .buttonStyle(.pressable)
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets())
                if let iconError {
                    Text(iconError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("App icon")
            }

            Section {
                Picker("Clock", selection: $customization.clock) {
                    ForEach(Customization.Clock.allCases) { clock in
                        Text(clock.label).tag(clock)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Times")
            } footer: {
                Text("Zulu is the clock ATIS, ATC and flight plans use. Flight stories you share stay in local time.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: customization.accent)
        .sensoryFeedback(.selection, trigger: currentIcon)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear { currentIcon = customization.currentAppIcon }
    }

    // MARK: - Swatches

    private func accentSwatch(_ accent: Customization.Accent) -> some View {
        let selected = customization.effectiveAccent == accent
        let locked = accent.requiresPro && !pro.isPro
        return VStack(spacing: 8) {
            Circle()
                .fill(accent.color)
                .frame(width: 46, height: 46)
                .overlay {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    } else if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? accent.color : .clear, lineWidth: 2.5))
            Text(accent.name)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(locked ? "Requires TailTrack Pro" : "")
    }

    private func iconTile(_ icon: Customization.AppIcon) -> some View {
        let selected = currentIcon == icon
        let locked = icon.requiresPro && !pro.isPro
        return VStack(spacing: 8) {
            Image(icon.previewImageName)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .padding(5)
                            .background(.thinMaterial, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5)
                )
            Text(icon.name)
                .font(.caption2.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Choosing

    private func choose(_ accent: Customization.Accent) {
        guard !accent.requiresPro || pro.isPro else {
            showingPaywall = true
            return
        }
        withAnimation(Motion.standard) { customization.accent = accent }
    }

    private func choose(_ icon: Customization.AppIcon) {
        guard !icon.requiresPro || pro.isPro else {
            showingPaywall = true
            return
        }
        iconError = nil
        Task {
            do {
                try await customization.setAppIcon(icon)
                currentIcon = icon
            } catch {
                iconError = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
    }
}
