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
