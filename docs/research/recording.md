# Screen recording and editing

Research for OpticalFlow. Done 2026-10-29.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.
Screen Studio changelog/pricing pages blocked; used homepage and press.

## Findings
- Cap: open source (AGPL app, MIT capture crates), Rust + Tauri. Capture via ScreenCaptureKit (`scap-screencapturekit`, cidre bindings), camera via AVFoundation, encoding via AVFoundation and an FFmpeg fork, rendering on wgpu, rnnoise for mic. Free tier records 4K60 with full editor; $58 lifetime. [V](https://github.com/CapSoftware/Cap) [V](https://cap.so/pricing)
- Screen Studio: $108/yr, subscription only since Oct 2025, Mac only, ScreenCaptureKit, autosaves every 2 s. [V](https://screen.studio/)
- CleanShot X: $35 one-time. 5.0 added Studio Mode: smart zooms, cursor smoothing, trim, motion blur, backgrounds, post-record camera edit. [V](https://cleanshot.com/changelog)
- Loom: free 5 min/720p, no trim or download; Business $18 adds trim, 4K; AI tier adds auto-chapters. [V](https://www.loom.com/pricing)
- OBS: free, display/window/app capture with desktop audio via SCK, no editor. System-audio-only capture unsupported. [V](https://github.com/obsproject/obs-studio/issues/10401)
- QuickTime / Shift-Cmd-5: free, screen or window or area, mic, pointer, trim, .mov, no system audio, no camera overlay. [V](https://support.apple.com/guide/mac-help/take-a-screenshot-or-screen-recording-mh26782/mac)
- SCK system audio over long sessions has crash reports on Apple forums. [V](https://developer.apple.com/forums/thread/775307)

## Likes and dislikes
| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Cap | instant start/record; open source, fast updates; cheap zoom effects; "switched from Loom" | crashes on record; multi-screen unreliable; slow Studio export; flicker in render; window capture grabs a region | PH, HN 41741422, HN 47595695, GH #1557 #1754 |
| Screen Studio | quality; intuitive editor; auto-zoom saves time; reliable | subscription switch; slow or stuck export; memory spikes; auto-zoom "dizzying"; 3 h = 40 GB; no clip import | PH, HN 47645554, alternativeto |
| Loom | instant link; transcripts; integrations | 5 min free cap; price jump; mic popups; sign-in bugs; basic editing | G2, Trustpilot, PH |
| CleanShot X | polished; fast cloud links; OCR; scrolling capture | yearly renewal; 400 MB memory; cloud videos vanish after 24 h | r/macapps quotes |
| OBS | free; streaming-grade; flexible | steep learning curve; black screens; wrong audio sources; no editor | Capterra, GH |
| QuickTime | free; zero setup | no system audio; no camera; .mov only | Apple |

Patterns: must have = display/window capture, mic, system audio, camera bubble, trim, MP4 export, reliability (every paid rival's top complaint is crashes or stuck exports). Our chance = chapters from completed tasks (nobody does non-AI chapters), one-time price, local-only, record tracks separately and autosave.

## Feature matrix
| Feature | Cap | Screen Studio | Loom | CleanShot | OBS | QuickTime | Version one? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Display / window capture | Y | Y | Y | Y | Y | Y | yes |
| Area capture | Y | Y | paid | Y | Y | Y | later |
| Camera bubble | Y | Y | Y | Y | source | N | yes (separate track) |
| Mic | Y | Y | Y | Y | Y | Y | yes |
| System audio | Y | Y | Y | Y | Y | N | yes |
| Cursor smoothing | Y | Y | N | Y | N | N | later |
| Auto-zoom on click | Y | Y | N | Y | N | N | later |
| Background padding | Y | Y | N | Y | N | N | later |
| Trim | Y | Y | paid | Y | N | Y | yes |
| Chapters | AI, Pro | N | AI, paid | N | N | N | yes, from completed tasks |
| Export MP4 1080p/4K | Y | Y | paid | Y | Y | .mov | yes |
| 9:16 / 1:1 presets | Y | Y | N | Y | N | N | no |
| Share link | Y | Y | Y | Y | N | N | no |
| Autosave during record | Y | Y (2 s) | ? | ? | Y | ? | yes |

## Decisions
1. Record with ScreenCaptureKit, screen + mic + system audio + camera as separate files, autosaved, because crashes and stuck exports are the top complaint of every rival [V PH, HN] and Cap/Screen Studio both use SCK [V]. Planned test: 30-minute SCK capture with system audio, check for the forum crash [V thread 775307].
2. Version one editing is trim only plus chapter markers; zoom, cursor smoothing, padding come later, because trim + zoom + padding + export is exactly what CleanShot 5 added last and the minimum people call "feels good" [V changelog].
3. Chapters come from tasks completed during the session, exported as a YouTube description timestamp list (0:00 first, at least 3, each at least 10 s), because nobody offers non-AI chapters and YouTube ignores embedded chapter tracks [V](https://support.google.com/youtube/video/13604742).
4. Local only, no share links, no AI, no 9:16, because the market's stated wish is a one-time price with local export [V HN].

## Open questions
- [U] Memory and disk for a 1-hour 4K60 capture. Measure; default to 1080p30 if over 10 GB/h.
