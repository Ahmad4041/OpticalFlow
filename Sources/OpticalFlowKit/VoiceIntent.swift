import Foundation

/// What a spoken or typed sentence asks for, without an AI model. The app's
/// built-in orchestrator runs these; Claude Code or Codex handle anything richer.
public enum VoiceIntent: Equatable, Sendable {
    case add(title: String)
    case complete(match: String)
    case start(match: String)
    case stop
    case setPriority(match: String, Priority)
    case addNote(match: String, note: String)
    case addSubtask(match: String, title: String)
    /// A chapter marker in the running recording.
    case mark(title: String?)

    private static let priorityWords = "urgent|high priority|high|medium priority|medium|normal|low priority|low|asap|critical"

    private struct Rule: @unchecked Sendable {   // NSRegularExpression is immutable and thread-safe
        let regex: NSRegularExpression
        let build: @Sendable ([String]) -> VoiceIntent
    }

    private static let rules: [Rule] = [
        rule(#"^(?:stop|end|finish)(?: the)?(?: current)? session$"#) { _ in .stop },
        rule(#"^(?:mark|clip) (?:that|this|it|here)$"#) { _ in .mark(title: nil) },
        rule(#"^(?:add )?(?:a )?(?:marker|chapter|bookmark)(?: here| now)?(?: called| named|:)? ?(.*)$"#) { .mark(title: $0.first.flatMap { $0.isEmpty ? nil : $0 }) },
        rule(#"^(?:add|create) (?:a |the )?(?:subtask|sub task|sub-task|step|checklist item) (?:to|on|for|under) (.+?)(?::| called| saying),? (.+)$"#) { .addSubtask(match: $0[0], title: $0[1]) },
        rule(#"^(?:add|create|make) (?:a |the )?note (?:to|on|for) (.+?)(?::| saying| that),? (.+)$"#) { .addNote(match: $0[0], note: $0[1]) },
        rule(#"^note (?:to|on|for) (.+?)(?::| saying| that),? (.+)$"#) { .addNote(match: $0[0], note: $0[1]) },
        rule(#"^(?:make|mark|set|flag) (.+?)(?: as| to)? (\#(priorityWords))(?: priority)?$"#) { .setPriority(match: $0[0], Priority.parse(word($0[1])) ?? .high) },
        rule(#"^(.+?) is (?:now )?(\#(priorityWords))(?: priority)?$"#) { .setPriority(match: $0[0], Priority.parse(word($0[1])) ?? .high) },
        rule(#"^(?:complete|finish|finished|done with|check off|mark done|close) (.+)$"#) { .complete(match: $0[0]) },
        rule(#"^(.+?) is (?:done|finished|complete)$"#) { .complete(match: $0[0]) },
        rule(#"^(?:start|begin|work on|focus on)(?: a)?(?: session on)? (.+)$"#) { .start(match: $0[0]) },
        rule(#"^(?:add|create|new)(?: a| the)?(?: new)? task(?: to| called| named|:)? (.+)$"#) { .add(title: $0[0]) },
        rule(#"^(?:add|remind me to|todo|to do) (.+)$"#) { .add(title: $0[0]) },
    ]

    /// Anything that matches no rule becomes a new task, so a plain sentence still lands somewhere.
    public static func parse(_ text: String) -> VoiceIntent {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = clean.last, ".!?".contains(last) { clean.removeLast() }
        let lower = clean.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        for rule in rules {
            guard let m = rule.regex.firstMatch(in: lower, range: range) else { continue }
            let groups = (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: lower).map { String(lower[$0]) } }
            return rule.build(groups)
        }
        return .add(title: clean)
    }

    private static func rule(_ pattern: String, _ build: @escaping @Sendable ([String]) -> VoiceIntent) -> Rule {
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), build: build)
    }

    /// "high priority" → "high".
    private static func word(_ phrase: String) -> String { String(phrase.split(separator: " ").first ?? "") }
}
