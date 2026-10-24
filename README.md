# NotraFree: an app for the Boya Notra NEO without a subscription

> **No Mac? Use the web version:** https://carlossampedroltd-pixel.github.io/Ghidra/
> It installs on the iPhone from Safari, adapts to the iPhone 17 Pro Max and the
> iPhone Duo (folded and open), and transcribes with Whisper on the device.
> Setup guide: [`docs/WEB_APP.md`](docs/WEB_APP.md).

An open-source iPhone app that replaces the official Boya app for the **Boya Notra
NEO** AI recorder:

- 🎙️ **Gets your recordings off the device**: over Bluetooth LE (using a configurable
  protocol profile), by importing files (USB-C, Files app, export from the
  official app), or by recording with the iPhone microphone.
- 📝 **Free, unlimited transcription** on the iPhone itself (Apple Speech, on-device).
  No monthly minutes and no external servers.
- ✨ **AI summaries** on the device with Apple Intelligence (iOS 26+, compatible
  iPhones), plus a simple summary on older devices.
- ☁️ **Everything in your Google Drive**: the audio and a `.md` file with the summary
  and transcript, in a "Boya Notra" folder. You can also pull audio back down from
  Drive.
- 🔬 **Built-in reverse-engineering toolkit**: GATT explorer, hex console, BLE log
  export, a btsnoop analyzer and a Ghidra script.

> ⚠️ **Honest status:** Boya hasn't published the NEO's BLE protocol. The app works
> right away with imports, iPhone recording, transcription, summaries and Drive.
> **Direct Bluetooth download** needs you to capture the protocol once, following
> [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md), and paste the result
> under Settings › BLE profile (no recompiling).

## Structure

```
web/                       web app (PWA): no build step, deployed to GitHub Pages
NotraFree/                 native iOS app (SwiftUI, iOS 17+, needs a Mac with Xcode)
  project.yml              XcodeGen spec (two targets: ProMax and Duo)
  Config/                  per-target xcconfigs: Team ID, bundle IDs, Google client IDs
  NotraFree/
    App/                   entry point and tabs
    BLE/                   CoreBluetooth + DeviceProfile (configurable protocol)
    Audio/                 WAV packing, format detection, iPhone recording
    AI/                    on-device transcription and summaries
    Drive/                 Google Drive v3 client (scope drive.file)
    Models/, Views/
tools/
  btsnoop_att.py           extracts ATT commands and notifications from an Android capture
  ble_probe.py             scans, dumps GATT and replays commands from a PC (bleak)
  ghidra/FindBleProtocol.java  Ghidra script: finds UUIDs and protocol strings in .so files
docs/REVERSE_ENGINEERING.md   step-by-step reverse-engineering guide
docs/INSTALACION_PERSONAL.md  install only on your iPhone, without the App Store
docs/WEB_APP.md               web version: setup, Google Drive, Bluefy for Bluetooth
```

## Two versions

The project builds two apps from the same code (different bundle IDs, so both can
be installed at once):

| Scheme | Device | Layout |
|---|---|---|
| **NotraFreeProMax** | iPhone 17 Pro Max | standard single-column tabs |
| **NotraFreeDuo** | iPhone Duo | folded (5.4"): same tabs. Unfolded (7.6"): three-column split view (sections, notes, detail) with summary and transcript side by side |

The Duo layout switches on available width, not device model, so it also adapts
when the app shares the screen with another app in Split View.

## Build and install on your iPhone only (no App Store)

Step-by-step guide: [`docs/INSTALACION_PERSONAL.md`](docs/INSTALACION_PERSONAL.md).
In short:

1. Put your Team ID and bundle prefix in `NotraFree/Config/Personal.xcconfig`, and
   one Google OAuth iOS client ID per app in `Config/ProMax.xcconfig` / `Config/Duo.xcconfig`.
2. `brew install xcodegen && cd NotraFree && xcodegen generate && open NotraFree.xcodeproj`
3. Turn on Developer Mode on the iPhone, connect it by cable, choose the scheme and
   press ▶︎. The signing profile only allows your registered devices. With a free
   Apple ID it expires after 7 days; with the paid program ($99/year), after 1 year.
4. On the iPhone, download the on-device dictation language: Settings › General ›
   Keyboard › Dictation languages.

## Use

| Tab | What it does |
|---|---|
| **Notes** | library, search, import files, record with the iPhone. Each note: playback, transcription, summary, upload to Drive. |
| **Recorder** | find and connect to the Notra NEO, download a recording by number, GATT explorer |
| **Drive** | Google sign-in, Drive folder, "upload everything pending", download audio from Drive |
| **Settings** | transcription language, automatic processing, BLE profile editor (JSON) |

The official Boya app only accepts one Bluetooth connection, so close it before
connecting with NotraFree.

## Privacy

There's no server. Audio is only processed on the iPhone and only goes to *your*
Google Drive, with the `drive.file` permission (the app can only see the files it
creates).
