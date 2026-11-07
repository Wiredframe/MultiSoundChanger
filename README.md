# MultiSoundChanger

Volume keys for macOS multi-output devices.

macOS disables the volume keys and the volume slider as soon as a multi-output device (created in Audio MIDI Setup) is the sound output. MultiSoundChanger steps in for exactly that case: it catches the volume keys, changes the volume of every device in the group and shows a small level indicator. For any other output it stays out of the way and macOS handles the keys as usual.

This is a slimmed-down rewrite of [rlxone/MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger) for current macOS.

## What it does

- **Volume up, down and mute** on the keyboard and the F-keys, with Shift + Option for quarter steps like macOS.
- **Keeps relative levels.** Every device and channel in the group is scaled proportionally, so if the headphones are set louder than the speakers, they stay louder. Channels set to 0 for a left/right speaker split stay at 0.
- **Menu bar slider** for the group volume, plus shortcuts to Sound Settings and Audio MIDI Setup.
- Optional: open at login, hide the menu bar icon (open the app again to bring it back).

Devices without a software volume control (many HDMI displays) cannot be controlled, neither by macOS nor by this app.

## Changes from the original

The original (2021) was 1,200 lines with CocoaPods, a checked-in private framework and several bugs. This fork is about 500 lines of Swift with no dependencies.

Fixed:

- All devices were set to one shared value, losing per-device levels and channel balance (upstream #19, #22, #30, #36).
- Volume keys stopped working after sleep or after some time, because macOS switches off a slow event tap and it was never re-enabled (#27, #18).
- The device list was read once at launch; new devices and output switches were ignored (#25).
- No Shift + Option fine steps (#20).
- The volume HUD relied on the private OSD framework, which no longer shows anything on current macOS.
- The menu bar icon could not be hidden (#8).
- No signed build, no Apple silicon build (#35, #23).

Removed: the output device list (Control Center does that), SwiftLint, the MediaKeyTap dependency, storyboards and the bundled OSD framework.

## Requirements

macOS 27 or later on Apple silicon. Accessibility access (System Settings › Privacy & Security › Accessibility), needed to receive the volume keys.

## Install

```sh
brew install --cask wiredframe/tap/multisoundchanger
```

The app is signed with a Developer ID but not notarized; the cask removes the quarantine flag.

## Build

```sh
./build.sh            # build/MultiSoundChanger.app
./build.sh --install  # copy to ~/Applications and launch
./build.sh --zip      # release archive
```

## License

Apache License 2.0, see [LICENCE](LICENCE). Original work © Dmitry Medyuho, modified by Ulf Schuster (Wiredframe).
