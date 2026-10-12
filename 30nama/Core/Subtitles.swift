import Foundation

struct Cue: Equatable {
    var start: Double
    var end: Double
    var text: String
}

/// WebVTT (and SRT, which differs only in details this parser already tolerates) subtitle track.
struct SubtitleTrack: Equatable {
    private(set) var cues: [Cue]

    init(cues: [Cue] = []) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    init(vtt text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = SubtitleTrack.timestamp(parts[0]),
                  let end = SubtitleTrack.timestamp(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)[0])
            else { continue }
            let body = SubtitleTrack.clean(lines[(timing + 1)...].joined(separator: "\n"))
            if !body.isEmpty { cues.append(Cue(start: start, end: end, text: body)) }
        }
        self.init(cues: cues)
    }

    /// "MM:SS.mmm" or "HH:MM:SS.mmm"; SRT uses a comma before the milliseconds.
    static func timestamp(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = s.split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        var total = 0.0
        for f in fields {
            guard let v = Double(f), v >= 0 else { return nil }
            total = total * 60 + v
        }
        return total
    }

    /// Strips markup (`<i>`, `<c.yellow>`), ASS position overrides (`{\an8}`) and decodes the few entities that occur in practice.
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\{\\an?\d\}"#, with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&lrm;", ""), ("&rlm;", "")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text to show at `t`, or an empty string.
    func text(at t: Double) -> String {
        guard !cues.isEmpty else { return "" }
        // Last cue starting at or before t.
        var lo = 0, hi = cues.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        // Cues can overlap, so look a few back for one that has not ended yet.
        var j = idx
        while j >= 0 && j > idx - 4 {
            if cues[j].end > t { return cues[j].text }
            j -= 1
        }
        return ""
    }
}
