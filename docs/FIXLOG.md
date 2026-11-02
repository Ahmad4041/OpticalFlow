# Fix log

## 2026-10-29 Two captures started at once; screen and cursor stuttered
Symptom: clicking Record once produced two files a second apart; the whole screen glitched and the cursor lagged while recording.
Cause: `SCContentSharingPicker` was given the observer on every `pick()`, and `didUpdateWith` can fire more than once. The `!isRecording` guard in `start` only held after the first stream had finished awaiting `startCapture`, so a second stream started in between. Two display captures plus HEVC encoding saturated an Intel i7.
Fix: add the observer once in `init`; take a synchronous `starting` lock before the first await (`claimStart`); encode H.264 (hardware on Intel, YouTube's recommendation); camera at 720p.
Rule: Any `async` start that must run once takes its lock before the first `await`, never after.

## 2026-10-29 Camera never recorded
Symptom: no `-camera.mov` sidecar appeared.
Cause: the camera defaulted to off, and the Settings toggles wrote `UserDefaults` that `Recorder` had already read at launch, so turning it on there did nothing.
Fix: camera on by default; Settings binds to `model.recorder` directly; toggles also sit in a toolbar Recording Options menu; a camera failure shows as text in the menu bar panel.
Rule: One owner per setting. A view binds to the object that uses the value, never to a parallel `@AppStorage` copy.

## 2026-10-29 "The camera does not record"
Symptom: the user saw no camera in the recording.
Cause: the sidecar .mov was written every time, but nothing showed the camera on screen, so a display capture never contained the user. Expectation was an OBS-style live overlay.
Fix: a round always-on-top camera bubble (NSPanel + AVCaptureVideoPreviewLayer) while the camera records; the display capture includes it.
Rule: A background artifact (a sidecar file) is invisible to the user. Every capture the app makes needs a visible sign while it runs.

## 2026-10-29 Crash (SwiftData assertion) after deleting the selected task
Symptom: "OpticalFlow quit unexpectedly", EXC_BAD_INSTRUCTION in SwiftData on the main thread, during the self-test.
Cause: `selection` still pointed at a task the test had deleted; `context.model(for:)` on a deleted id asserts when the toolbar re-rendered.
Fix: `AppModel.selected()` uses `registeredModel(for:)` and checks `isDeleted`, so every reader of the selection gets nil.
Rule: Resolve a stored PersistentIdentifier through one guarded accessor; never call `context.model(for:)` on an id that may be gone.

## 2026-10-31 Self-test and snapshots hung with no output; the app had no window
Symptom: `tools/selftest.sh` printed nothing and never exited; a plain launch from the agent's shell showed no window on any Space, even for commits that had passed before.
Cause: the agent's shell was sandboxed in this session. A process it spawns cannot connect to WindowServer, so NSApplication runs its event loop with no windows and the `.task` that starts the self-test never fires.
Fix: both scripts launch the app through `open -W --stdout --stderr --env`, so LaunchServices starts it outside the shell's sandbox.
Rule: Launch GUI apps for checks through `open`, never by exec'ing the binary; and when a tool prints nothing, probe the window list before suspecting the code.

## 2026-10-31 Crash (swift_dynamicCast abort) when a recording was selected
Symptom: SIGABRT in `AppModel.selected<A>()` from the Task menu, right after selecting a recording.
Cause: `ModelContext.registeredModel(for:) as T?` aborts instead of returning nil when the id belongs to another entity. The previous fix for deleted rows introduced this.
Fix: check `PersistentIdentifier.entityName` against the requested type before the typed lookup.
Rule: A typed SwiftData lookup needs an entity check first; `as T?` on SwiftData APIs is not a safe cast.

## 2026-10-31 Crash (getSuperclassMetadata abort) when opening a recording with a file
Symptom: SIGABRT inside `_AVKit_SwiftUI` while SwiftUI laid out the recording detail.
Cause: SwiftUI's `VideoPlayer` is a generic over AVKit's `AVPlayerView`; in this Swift package build its superclass metadata is not resolvable at runtime and the Swift runtime aborts. Snapshots never caught it because the seed recording had no file, so the player branch never rendered.
Fix: a hand-written `NSViewRepresentable` around `AVPlayerView`. Seed data now writes a real 4 s clip so the player renders in every snapshot run.
Rule: Seed data must exercise every branch a page can show; a branch that snapshots never render is untested.

## 2026-10-31 Recording detail showed "No Selection" with a row highlighted
Symptom: in snapshots the Recordings page selected its first row but the detail stayed empty; the self-test passed.
Cause: `selected()` used `registeredModel(for:)`, which returns nil for a row no object holds. The self-test kept the recording in a local, the snapshot did not.
Fix: fetch by `persistentModelID` with a limit of one; nil for a deleted row, found for an unreferenced one.
Rule: A self-test must not keep references the real app would not keep; check through the same path the UI uses, or hold nothing.

## 2026-10-31 Recordings were silent
Symptom: a 40 s recording had a stereo AAC track with RMS 0 and peak 0.
Cause: `captureMicrophone` was set without ever requesting microphone access. ScreenCaptureKit does not raise the TCC prompt; the system log showed no microphone decision for the app. The mixed track came out as zeros.
Fix: `AVCaptureDevice.requestAccess(for: .audio)` before starting; capture the mic only when authorized; say where to allow it otherwise.
Rule: Every capture device needs its own permission request before use; a framework that consumes the device does not ask on your behalf.

## 2026-10-31 Camera bubble showed a white circle inside a square
Cause: the preview layer was installed as the view's own layer after `wantsLayer`, and the window shadow was computed from a square alpha mask.
Fix: layer-hosting view with a clear host layer and the preview as a sublayer; no window shadow.
Rule: For a custom layer on NSView, assign `layer` first, then `wantsLayer = true`, and keep a clear host layer.

## 2026-10-31 No controls on screen while recording
Fix: the mini timer floats up when a recording starts, with a red Stop Recording button, and hides when the recording ends with no session running.
Rule: Any long-running capture shows a visible control to stop it without hunting through menus.

## 2026-10-31 Snapshot run hung with no output while the real app was open
Cause: the test instance bound the agent socket at the default path, which the running app already owned; `listen` unlinked and rebound it and the two instances contended before the main view's task got to the snapshot code.
Fix: `tools/snap.sh` and `tools/selftest.sh` set `APP_AGENT_SOCKET` to a /tmp path, as `check-agent-cli.sh` already did.
Rule: Every test launch isolates every shared resource the app opens: the store, the movie folder, and the socket.

## 2026-10-31 Voice panel heard nothing; recordings had silent audio
The built-in "MacBook Pro Microphone" on this Mac delivers 48 kHz float buffers of exact zeros to every app; the HyperX QuadCast S delivers signal. Both the voice panel and ScreenCaptureKit read the system default input, so both were silent while permissions were fine. Found by measuring the peak sample level in the tap (`opticalflow agent state`) and by recognizing a generated file (`agent transcribe`), which separated the microphone from recognition.
Fix: a Microphone preference (Settings > Agent and > Recording) that the audio engine and `SCStreamConfiguration.microphoneCaptureDeviceID` both use; the panel warns after two seconds of zeros.
Rule: when audio is silent, measure the input level before blaming permissions, and let people choose the device; the system default is not always the one that works.

## 2026-10-31 Opening an older task crashed after the subtasks build
Cause: the new `checklist` column was a non-optional Codable array. Rows from before the column had no value, and SwiftData asserts when it decodes a missing value into a non-optional array (scalars get their default; arrays do not).
Fix: the stored property is optional; `subtasks` reads it as an empty list. Verified by nulling the column in a test store and reading the task.
Rule: A new Codable or array attribute on a @Model is optional with a computed non-optional accessor. Only scalars get a default on migration.

## 2026-10-31 Sessions page crashed after a task was deleted
Cause: `Session.task` had no inverse, so deleting a task left sessions pointing at a row that no longer existed; reading `task?.isDone` in the list asserted inside SwiftData.
Fix: `TaskItem.sessions` is the inverse with nullify; `delete(task)` also clears the pointer by hand. Stores from before are repaired with one SQL UPDATE before the container opens (`Store.repair`): SwiftData aborts on clearing the pointer too, so a first attempt through the model crashed at launch.
Rule: Every optional relationship on a @Model declares its inverse and delete rule, and the self-test reads the other side after a delete. Repairs of broken rows run in SQL before SwiftData opens the file.

## 2026-10-31 The app "crashed" with no crash report while a build ran
Cause: `build.sh` deleted and rewrote `~/Applications/OpticalFlow.app` while that app was running. macOS kills a running process whose signed binary changed on disk, and writes no report.
Fix: the build is assembled in a staging folder; tests run the staged copy; the installed app is replaced only when it is not running, or with `--open`, which quits it first.
Rule: Never overwrite a running app's bundle. Stage builds, test the staged copy, and install when the user is ready.

## 2026-11-02 Self-test failed on a clean checkout: "camera on by default" was false
Symptom: `tools/selftest.sh` reported 1 of 136 checks failing on one Mac and passing on another.
Cause: the self-test and snapshots read and wrote `UserDefaults.standard`, the same preferences the person uses in the real app. Their camera was off, so the test saw it off; test runs also leaked their own writes (microphone, orchestrator) into real preferences.
Fix: `Prefs.store` in App.swift. With `APP_STORE` set it is a separate suite, emptied at launch; otherwise it is `.standard`. Every preference read and write in the app goes through it, including `@AppStorage(…, store:)`.
Rule: a test run touches nothing the user owns: not the store, not the preferences, not the installed app.

## 2026-11-02 Control Strip item showed "25" instead of the countdown
Symptom: with another app in front, the Touch Bar's Control Strip item read "25" or "24", the rest clipped.
Cause: a collapsed Control Strip item is about 50 pt wide, fixed by the system. The glyph plus " 24:58" never fit; neither did the glyph plus "24m".
Fix: the item is the glyph when idle and three characters of text when a session or break runs ("24m", "+3m"), red while recording. Verified with `screencapture -b` from Finder.
Rule: a Control Strip item gets one glyph or three characters. Put anything longer in the modal bar behind the tap.
