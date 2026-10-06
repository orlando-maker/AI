import AVFoundation
import Observation

/// Plays live airband audio from receivers the pilot owns or has
/// permission to use, typically RTLSDR-Airband on a Raspberry Pi streaming
/// through Icecast. TailTrack never plays LiveATC.net feeds in-app: their
/// terms forbid third-party apps tuning their streams, so the app links out
/// to LiveATC instead.
@Observable
@MainActor
final class RadioPlayer {
    private(set) var streams: [RadioStream] = []
    private(set) var playing: RadioStream?
    private(set) var isBuffering = false
    var errorMessage: String?

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private static let storageKey = "radioStreams"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([RadioStream].self, from: data) {
            streams = saved
        }
    }

    /// Adds a stream; returns false when the address isn't a web URL.
    @discardableResult
    func add(name: String, address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        let label = name.trimmingCharacters(in: .whitespaces)
        streams.append(RadioStream(name: label.isEmpty ? (url.host ?? "My receiver") : label, url: url))
        save()
        return true
    }

    func delete(at offsets: IndexSet) {
        if let playing, offsets.contains(where: { streams[$0].id == playing.id }) { stop() }
        streams.remove(atOffsets: offsets)
        save()
    }

    func toggle(_ stream: RadioStream) {
        if playing?.id == stream.id { stop() } else { play(stream) }
    }

    func play(_ stream: RadioStream) {
        stop()
        errorMessage = nil
        do {
            // .playback keeps the audio going with the screen locked (the
            // app declares the audio background mode).
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            errorMessage = "Audio couldn't start: \(error.localizedDescription)"
            return
        }
        let item = AVPlayerItem(url: stream.url)
        let player = AVPlayer(playerItem: item)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.playing?.id == stream.id else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                case .failed:
                    self.stop()
                    self.errorMessage = "Couldn't play \(stream.name). \(message ?? "Check the stream address.")"
                default:
                    break
                }
            }
        }
        self.player = player
        playing = stream
        isBuffering = true
        player.play()
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        playing = nil
        isBuffering = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(streams) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// LiveATC.net's listing for an airport. Linking out is fine; playing
    /// their streams inside another app is not.
    static func liveATCURL(for ident: String) -> URL? {
        URL(string: "https://www.liveatc.net/search/?icao=\(ident.lowercased())")
    }
}
