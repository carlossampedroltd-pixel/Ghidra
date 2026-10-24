# NotraFree: an app for the Boya Notra NEO without a subscription

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
NotraFree/                 iOS app (SwiftUI, iOS 17+)
  project.yml              XcodeGen spec
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
docs/REVERSE_ENGINEERING.md   step-by-step guide
```

## Build (requires a Mac with Xcode 16+)

1. `brew install xcodegen && cd NotraFree && xcodegen generate && open NotraFree.xcodeproj`
2. **Google OAuth** (once):
   - In [Google Cloud Console](https://console.cloud.google.com/), create a project
     and enable the **Google Drive API**.
   - Set up the OAuth consent screen ("External", add your email as a test user).
   - Credentials › Create OAuth client ID › **iOS**, with the bundle id
     `com.example.notrafree` (or whatever you use in `project.yml`).
   - In `NotraFree/Info.plist`, replace `YOUR_CLIENT_ID` in `GIDClientID` and in
     the URL scheme (`com.googleusercontent.apps.<...>`) with your values.
3. Choose your Apple ID under Signing & Capabilities and run it on your iPhone.
   With a free Apple account the app expires after 7 days. Reinstall it, or use a
   paid developer account ($99/year) or AltStore/SideStore.
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
