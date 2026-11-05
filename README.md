# Prog Radio for macOS

A menu bar player for [progradio.com](https://www.progradio.com) with desktop widgets and a Control Center control.

- **Menu bar:** pick The Crimson Hall, The Wizard's Forest or The Dragon's Tower, play/stop, volume, now playing with artwork, recently played, launch at login.
- **Control Center / media keys:** the current track shows in the Now Playing module; ⏯ toggles, ⏭/⏮ switch channels.
- **Widgets:** *Now Playing* (small/medium/large, choose the channel in Edit Widget) and *All Channels* (medium/large; click a channel to listen).
- **Control:** a *Prog Radio* control for Control Center or the menu bar that plays/stops a chosen channel.

Streams are the 320 kbps AAC radio.co links from progradio.com/listen. Now-playing data comes from `public.radio.co/stations/<id>/status`.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make install   # builds Release, copies to ~/Applications, launches
make test
make log       # app logs
```

The app is signed ad hoc. Widgets are refreshed by WidgetKit about every 5 minutes, and immediately when the track changes while the app is running.

`progradio://play/<crimson|wizard|dragon>`, `progradio://toggle[/<channel>]` and `progradio://stop` control the app from scripts and Shortcuts.
