# Architecture review, 2026-11-03 (end of M9, 51 stories done)

Survey: hottest files in 30 days are SelfTest (34 commits), AppModel (30), ContentView (27). Largest: VoiceAgent 876 lines, AppModel 683, SelfTest 578, AgentCommands 461. No drifted private structs. Fix log: 20 entries; the two newest are both AVFoundation lifetime or timing (asset released under its track, a slow capture read as a hang).

## Voice views out of VoiceAgent  [Strong]  — done in this check-in
Files: Sources/OpticalFlow/VoiceAgent.swift (876 lines: Orchestrator, AgentJob, VoiceAgent, VoiceError, VoiceView, VoiceAvatar, Microphone, MicrophonePicker, AgentActivityButton, AgentJobsList).
Signal: file over 600 lines; 14 commits in 30 days.
Problem: a change to the panel's look and a change to how a job runs land in the same file; the views read only public state of `VoiceAgent` and `AgentJob`, so the seam is already there.
Proposal: `VoiceViews.swift` holds the six view and picker types and `Microphone`; `VoiceAgent.swift` keeps the orchestrator, the job, the recognizer, the runner, and the panel. Pure move, no type changes.
Proof: build with no warnings, self-test 141 before and after, voice and agentjobs snapshots unchanged.
Plan: one commit.

## Export options as one value  [Worth exploring]
Files: AppModel.trim (6 parameters), RecordingDetail.export, AgentCommands "recordings export", SelfTest (nine calls).
Signal: the fourth Bool (`removeSilence`) landed in M9; the 2026-10-31 review said a fourth would tip it.
Proposal: `struct ExportOptions { var camera = false, followCursor = false, youtube = false, removeSilence = false }` in the Kit, passed as one argument; `Exporter.export` takes it too. The file suffix moves next to it (`options.suffix`), which the model builds by hand today.
Benefits: one place to add the next option; the CLI maps flags to fields in a loop.
Proof: the self-test's S-009, S-012, S-027, S-028, S-031, S-050 checks, same file names.
Plan: add the struct and a `trim(_:start:end:options:)` overload; move the three callers; delete the old signature.

## AppModel at 683 lines  [Speculative]
It holds tasks, projects, sessions, breaks, idle, export, URL commands, voice helpers. Sections are clear and each has its own self-test block. Split only when a feature needs to mock one of them.

## Considered, not recommended
- A `Silence` analyzer protocol with a test adapter: the self-test feeds `Exporter.levels` a synthesized clip, which is the real path. One conformer would be a hypothetical seam.
- Moving `TestVideo` out of SelfTest: used once, by the self-test, and the audio writer is 40 lines.

Top recommendation: the voice views move (done). Next: `ExportOptions` when the fifth export option is asked for.
