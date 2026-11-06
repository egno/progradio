import AppKit
import SwiftUI

@main
struct ProgRadioApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(player: delegate.player, notifier: delegate.notifier, votes: delegate.votes)
        } label: {
            MenuBarLabel(player: delegate.player)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let player = RadioPlayer()
    let notifier = TrackNotifier()
    let votes = SongVotes()
    private var systemNowPlaying: SystemNowPlaying?

    func applicationDidFinishLaunching(_ notification: Notification) {
        systemNowPlaying = SystemNowPlaying(player: player)
        player.onTrackChange = { [notifier] channel, track, artwork in
            notifier.post(track, channel: channel, artwork: artwork)
        }
    }

    /// `progradio://` links from the widgets and Control Center controls.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = AppLink(url: url) { player.handle(link) }
        }
    }
}

struct MenuBarLabel: View {
    let player: RadioPlayer

    var body: some View {
        switch player.state {
        case .stopped: Image(systemName: "dot.radiowaves.left.and.right")
        case .buffering, .reconnecting: Image(systemName: "antenna.radiowaves.left.and.right")
        case .playing: Image(systemName: player.channel.symbol)
        }
    }
}
