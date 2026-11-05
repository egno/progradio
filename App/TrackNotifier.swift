import AppKit
import Observation
import UserNotifications
import os

private let log = Logger(subsystem: "io.github.egno.ProgRadio", category: "notifications")

/// Optional banner for each new track on the channel being played. Off by default.
@MainActor
@Observable
final class TrackNotifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var isEnabled: Bool
    /// Set when macOS has notifications for the app turned off.
    private(set) var isBlocked = false

    private let defaults: UserDefaults
    private static let key = "notifyTrackChanges"
    private static let identifier = "track"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
        super.init()
        UNUserNotificationCenter.current().delegate = self
        if isEnabled { Task { await refreshAuthorization() } }
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.key)
        guard enabled else {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            isBlocked = !granted
        } catch {
            log.error("authorization: \(error.localizedDescription, privacy: .public)")
            isBlocked = true
        }
    }

    private func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isBlocked = settings.authorizationStatus == .denied
    }

    func post(_ track: Track, channel: Channel, artwork: NSImage?) {
        guard isEnabled, !isBlocked else { return }
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.subtitle = track.artist
        content.body = channel.name
        content.threadIdentifier = channel.rawValue
        if let artwork, let attachment = Self.attachment(artwork) {
            content.attachments = [attachment]
        }
        // One identifier, so each track replaces the last instead of piling up in Notification Center.
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("post: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private static func attachment(_ image: NSImage) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        // The system moves the file into its own store, so each post needs a fresh one.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "artwork", url: url)
        } catch {
            log.error("artwork: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // The app is an agent, and the popover makes it active; show banners anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
