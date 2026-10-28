# macOS platform

Research for OpticalFlow. Done 2026-10-29.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.
Target: macOS 26, Swift 6, SwiftUI, no Electron, no FFmpeg.

## Findings
- SCContentFilter: display, window, display excluding apps or windows. Audio filters only at app level. [V](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- SCStreamConfiguration: `capturesAudio` (13+) for system audio; `captureMicrophone` + `microphoneCaptureDeviceID` (15+). [V](https://developer.apple.com/videos/play/wwdc2024/10088/)
- SCRecordingOutput (15+): outputURL, fileType, codec; SCK does the asset writing. Mic + system audio come mixed in one track; the two-track option `mixesAudioWithMicrophone` is macOS 27 only. [V](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration/mixesaudiowithmicrophone)
- Forum report of a corrupt MP4 when captureMicrophone is on with SCRecordingOutput. [V](https://developer.apple.com/forums/thread/805892) [U] on 26.
- Camera cannot be injected into SCRecordingOutput. Options: record camera to a sidecar file with AVCaptureMovieFileOutput, or show a camera panel on screen and let the capture include it. [V](https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example)
- SCContentSharingPicker (14+): system picker, no Screen Recording TCC prompt and no monthly "allow for one month" nag for picked content. [V](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker) [V](https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/)
- There is no sandbox entitlement for screen capture; `com.apple.security.screen-capture` does not exist. [V](https://developer.apple.com/forums/thread/778616)
- AVCaptureSession needs NSCameraUsageDescription, NSMicrophoneUsageDescription, and entitlements `com.apple.security.device.camera` and `.audio-input`. [V](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.camera)
- YouTube: MP4 H.264 High + AAC-LC 48 kHz recommended; HEVC accepted. [V](https://support.google.com/youtube/answer/1722171)
- YouTube ignores embedded chapter tracks. Chapters come only from description timestamps: first is 0:00, at least 3, each at least 10 s. [V](https://support.google.com/youtube/video/13604742)
- QuickTime chapters need an AVAssetWriter text track with `chapterList` association, MOV only, fiddly. [V](https://developer.apple.com/forums/thread/745696)
- Trim: AVMutableComposition + AVAssetExportSession passthrough. [K]
- MenuBarExtra: `.menu` or `.window` style. Label font/width ignored, so a per-second countdown jitters with proportional digits; a Timer in `.menu` content stops while the menu is open; `.window` content misses App-struct @State. Fallback: NSStatusItem + NSPopover. [V](https://developer.apple.com/forums/thread/726565) [V](https://developer.apple.com/forums/thread/720625)
- Global hotkeys: Carbon RegisterEventHotKey needs no permission and works sandboxed (deprecated but used by Chromium). NSEvent global monitor and CGEvent tap need Accessibility or Input Monitoring. [V](https://www.quicopy.com/blog/macos-sandbox-keyboard-shortcuts) [V](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))
- SwiftData + CloudKit sync: needs paid Developer Program, no `.unique`, optional relationships, additive schema. EventKit Reminders would sync reminders only, not projects or sessions. [V](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- UNUserNotificationCenter needs a signed .app with a bundle id; no sandbox entitlement. [V](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)

## Feature matrix
| Feature | API | Permission | Risk | Version one? |
| --- | --- | --- | --- | --- |
| Screen + system audio + mic to file | SCStream + SCRecordingOutput | picker: none; mic TCC | mic corruption report [U]; one mixed audio track until 27 | yes |
| Pick what to record | SCContentSharingPicker | none | low | yes |
| Camera | AVCaptureSession to sidecar MOV | camera TCC + entitlement | no native compositing | yes (sidecar) |
| Trim | AVMutableComposition + ExportSession | none | low | yes |
| Chapters | text file + clipboard | none | none | yes |
| Embedded chapters | AVAssetWriter chapterList | none | fiddly, YouTube ignores | no |
| Menu bar timer | MenuBarExtra `.window` | none | jitter, state bugs | yes, monospaced digits |
| Global hotkey | RegisterEventHotKey | none | deprecated Carbon | yes |
| Tasks, sessions, recordings | SwiftData local | none | low | yes |
| Sync | SwiftData + CloudKit | paid account | schema limits | no |
| Break reminder | UserNotifications | user auth | low | later |

## Decisions
1. Record with SCRecordingOutput through SCContentSharingPicker, because it removes the Screen Recording prompt and the monthly nag entirely [V]. Planned test: record 2 minutes with captureMicrophone on and open the file in QuickTime, to check the corruption report [U].
2. Camera goes to a sidecar MOV via AVCaptureMovieFileOutput, composited later, because SCRecordingOutput cannot take a camera input [V].
3. Chapters are a description text file (0:00 first, 10 s minimum) copied to the clipboard, because YouTube reads nothing else [V].
4. Menu bar countdown uses MenuBarExtra `.window` with monospaced digits and an ObservableObject timer, because the App-struct @State bug and label jitter are documented [V]. Fall back to NSStatusItem if it still misbehaves.
5. Global hotkey uses RegisterEventHotKey, because it needs no permission [V].
6. Local SwiftData only, no sync, because CloudKit needs a paid account and EventKit would not hold sessions [V].

## Open questions
- [U] captureMicrophone + SCRecordingOutput corruption on macOS 26. Test in decision 1.
- [U] Memory and disk of 1 hour HEVC 1080p30 via SCRecordingOutput. Measure.
