import Foundation

/// 塔ラン中にプレイヤーが振り返るための時系列イベント。
public struct DungeonRunLogEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case damage
        case healing
        case acquisition
        case blocked
    }

    public static let maximumEntryCount = 80

    public let sequence: Int
    public let floorNumber: Int
    public let turn: Int
    public let point: GridPoint?
    public let kind: Kind
    public let hpBefore: Int?
    public let hpAfter: Int?
    public let message: String

    public var id: Int { sequence }

    public init(
        sequence: Int,
        floorNumber: Int,
        turn: Int,
        point: GridPoint?,
        kind: Kind,
        hpBefore: Int? = nil,
        hpAfter: Int? = nil,
        message: String
    ) {
        self.sequence = max(sequence, 0)
        self.floorNumber = max(floorNumber, 1)
        self.turn = max(turn, 0)
        self.point = point
        self.kind = kind
        self.hpBefore = hpBefore
        self.hpAfter = hpAfter
        self.message = message
    }

    public var headerText: String {
        var parts = ["\(floorNumber)F", "\(turn)手"]
        if let point {
            parts.append("(\(point.x),\(point.y))")
        }
        return parts.joined(separator: " / ")
    }

    public var symbolName: String {
        switch kind {
        case .damage:
            return "heart.slash"
        case .healing:
            return "cross.fill"
        case .acquisition:
            return "sparkles"
        case .blocked:
            return "shield.fill"
        }
    }

    public static func trimmed(_ entries: [DungeonRunLogEntry]) -> [DungeonRunLogEntry] {
        guard entries.count > maximumEntryCount else { return entries }
        return Array(entries.suffix(maximumEntryCount))
    }
}
