import AppKit
import MediaPlayer

/// Publishes the current track to Control Center's Now Playing module and the media keys.
@MainActor
final class SystemNowPlaying {
    private let player: RadioPlayer

    init(player: RadioPlayer) {
        self.player = player
        registerCommands()
        player.onChange = { [weak self] in self?.update() }
        update()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.stop()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.player.stop()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.player.toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.player.step(1)
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.player.step(-1)
            return .success
        }
    }

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard player.isActive else {
            center.playbackState = .stopped
            center.nowPlayingInfo = nil
            return
        }
        let track = player.current?.track
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track?.title ?? player.channel.name,
            MPMediaItemPropertyArtist: track?.artist ?? "Prog Radio",
            MPMediaItemPropertyAlbumTitle: "Prog Radio · \(player.channel.name)",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: player.state == .playing ? 1.0 : 0.0,
        ]
        if let image = player.currentArtwork {
            info[MPMediaItemPropertyArtwork] = Self.artwork(image)
        }
        center.nowPlayingInfo = info
        center.playbackState = player.state == .playing ? .playing : .paused
    }

    /// MediaPlayer calls the request handler on its own queue, so it must not inherit main-actor isolation.
    nonisolated private static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
