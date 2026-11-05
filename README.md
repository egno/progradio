# Prog Radio Menu Bar

An unofficial menu bar player for [progradio.com](https://www.progradio.com) with desktop widgets and a Control Center control.

- **Menu bar:** pick The Crimson Hall, The Wizard's Forest or The Dragon's Tower, play/stop, volume, now playing with artwork, recently played, launch at login.
- **Control Center / media keys:** the current track shows in the Now Playing module; ⏯ toggles, ⏭/⏮ switch channels.
- **Find a track:** search the current or a recent song on Apple Music, Spotify, Bandcamp or YouTube, or copy it (the ⋯ button, or right-click a recent track).
- **Track notifications** (off by default): a banner when a new song starts on the channel you're playing.
- **Reconnects by itself** after a dropped stream, a network change or waking from sleep.
- **AirPlay:** pick speakers from the popover; when sound goes to AirPlay, the app switches to the station's AirPlay stream.
- **Widgets:** *Now Playing* (small/medium/large, choose the channel in Edit Widget), *All Channels* (medium/large; click a channel to listen) and *Shows* (upcoming shows from the station's schedule, with links to request a song, song history, chat and supporting the station).
- **Control:** a *Prog Radio* control for Control Center or the menu bar that plays/stops a chosen channel.

Streams are the 320 kbps AAC radio.co links from progradio.com/listen, or its HLS AirPlay streams. Now-playing data comes from `public.radio.co/stations/<id>/status`, and only the playing channel is polled unless the menu is open. The *Shows* widget reads the schedule data embedded in progradio.com/showschedule, so it can break if the site changes.

## Install

Requires macOS 26 (Tahoe) or later.

```sh
brew install --cask egno/tap/progradio
```

Or download `ProgRadioMenuBar-<version>.dmg` from [Releases](https://github.com/egno/progradio/releases) and drag the app to Applications. The app isn't notarized, so macOS blocks the first launch of a downloaded copy; clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine "/Applications/Prog Radio Menu Bar.app"
```

To add widgets: right-click the desktop → Edit Widgets → Prog Radio Menu Bar. To add the control: Control Center → Edit Controls → Prog Radio Menu Bar.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make install   # builds Release, copies to ~/Applications, launches
make test
make log       # app logs
make release   # universal build/ProgRadioMenuBar-<version>.dmg and .zip
make cask TAP=~/proj/homebrew-tap   # Casks/progradio.rb for that DMG
```

The app is signed ad hoc. Widgets are refreshed by WidgetKit about every 5 minutes, and immediately when the track changes while the app is running.

`progradio://play/<crimson|wizard|dragon>`, `progradio://toggle[/<channel>]` and `progradio://stop` control the app from scripts and Shortcuts. `progradio://site/<schedule|request|history|chat|support>` opens that progradio.com page.

## Bugs and ideas

Please report them at [github.com/egno/progradio/issues](https://github.com/egno/progradio/issues). The menu bar popover has a **Report a bug** link too.

## License

[MIT](LICENSE). This is an unofficial app, not affiliated with Prog Radio. The streams, track data and the Prog Radio name belong to [progradio.com](https://www.progradio.com).
