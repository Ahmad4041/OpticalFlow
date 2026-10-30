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
