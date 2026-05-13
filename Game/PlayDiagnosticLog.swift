import Foundation
import SharedSupport

enum PlayDiagnosticLog {
    static func emit(
        event: String,
        fields: [(String, String)] = [],
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let parts = ["[PLAY]", "event=\(encoded(event))"] + fields.map { key, value in
            "\(key)=\(encoded(value))"
        }
        debugLog(parts.joined(separator: " "), file: file, line: line, function: function)
    }

    static func describe(_ point: GridPoint?) -> String {
        guard let point else { return "nil" }
        return "(\(point.x),\(point.y))"
    }

    static func describe(_ points: [GridPoint]) -> String {
        guard !points.isEmpty else { return "[]" }
        return "[" + points.map(describe).joined(separator: ",") + "]"
    }

    static func describe(_ points: Set<GridPoint>) -> String {
        describe(points.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        })
    }

    private static func encoded(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let needsQuotes = value.contains { character in
            character.isWhitespace || character == "\""
        }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

extension DungeonRelicAcquisitionPresentation.Item {
    var diagnosticDescription: String {
        switch self {
        case .relic(let relic):
            return "relic:\(relic.relicID.rawValue)"
        case .curse(let curse):
            return "curse:\(curse.curseID.rawValue)"
        case .mimicDamage(let damage):
            return "mimicDamage:\(damage)"
        case .hpCompensation(let amount):
            return "hpCompensation:\(amount)"
        }
    }
}
