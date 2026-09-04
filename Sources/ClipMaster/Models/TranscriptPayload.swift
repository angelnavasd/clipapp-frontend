import Foundation

// MARK: - Ingestion & Whisper Models

public struct WordTimestamp: Codable, Identifiable, Equatable, Hashable {
    public var id: String { "\(word)_\(start)" }
    public let word: String
    public let start: Double
    public let end: Double
    public var db: Double?
    public var isFiller: Bool?
    public var isDeleted: Bool = false // Marca si el usuario la eliminó en el editor

    public init(
        word: String,
        start: Double,
        end: Double,
        db: Double? = nil,
        isFiller: Bool? = nil,
        isDeleted: Bool = false
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.db = db
        self.isFiller = isFiller
        self.isDeleted = isDeleted
    }
}

public struct SilenceGap: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct TranscriptPayload: Codable {
    public let videoId: String
    public let language: String?
    public let videoDuration: Double
    public var words: [WordTimestamp]
    public var silenceGaps: [SilenceGap]?
    public var targetDuration: String?
    public var genre: String?
    public var targetClipCount: Int?
    public var sceneCuts: [Double]?

    public init(
        videoId: String,
        language: String? = nil,
        videoDuration: Double,
        words: [WordTimestamp],
        silenceGaps: [SilenceGap]? = nil,
        targetDuration: String? = nil,
        genre: String? = nil,
        targetClipCount: Int? = 4,
        sceneCuts: [Double]? = nil
    ) {
        self.videoId = videoId
        self.language = language
        self.videoDuration = videoDuration
        self.words = words
        self.silenceGaps = silenceGaps
        self.targetDuration = targetDuration
        self.genre = genre
        self.targetClipCount = targetClipCount
        self.sceneCuts = sceneCuts
    }
}

// MARK: - EDL Backend Response Models

public struct TimeRange: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double {
        max(0, end - start)
    }
}

public struct CutSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(start)_\(end)_\(reason)" }
    public var start: Double
    public var end: Double
    public var reason: String

    public init(start: Double, end: Double, reason: String) {
        self.start = start
        self.end = end
        self.reason = reason
    }
}

public struct HighlightWord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(word)_\(timestamp)" }
    public var word: String
    public var timestamp: Double
    public var color: String
    public var sfx: String

    public init(word: String, timestamp: Double, color: String, sfx: String) {
        self.word = word
        self.timestamp = timestamp
        self.color = color
        self.sfx = sfx
    }
}

public struct StoryBeat: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(start)_\(end)" }
    public let start: Double
    public let end: Double
    public let role: String
    public let text: String
    // F2/F5: anotaciones del backend (opcionales para backward-compat con EDLs viejos)
    public var needsFace: Bool?
    public var energyScore: Int?
    public var sentenceIds: [String]?

    public init(start: Double, end: Double, role: String, text: String, needsFace: Bool? = nil, energyScore: Int? = nil, sentenceIds: [String]? = nil) {
        self.start = start
        self.end = end
        self.role = role
        self.text = text
        self.needsFace = needsFace
        self.energyScore = energyScore
        self.sentenceIds = sentenceIds
    }

    public var duration: Double {
        max(0, end - start)
    }
}

public struct ClipDecision: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var viralScore: Int
    public var hook: String
    public var timeRange: TimeRange
    public var cutSegments: [CutSegment]
    public var highlightWords: [HighlightWord]
    public var storyBeats: [StoryBeat]?
    public var detectedFramingMode: String?
    public var webcamCorner: String?

    public init(
        id: String,
        title: String,
        viralScore: Int,
        hook: String,
        timeRange: TimeRange,
        cutSegments: [CutSegment],
        highlightWords: [HighlightWord],
        storyBeats: [StoryBeat]? = nil,
        detectedFramingMode: String? = nil,
        webcamCorner: String? = nil
    ) {
        self.id = id
        self.title = title
        self.viralScore = viralScore
        self.hook = hook
        self.timeRange = timeRange
        self.cutSegments = cutSegments
        self.highlightWords = highlightWords
        self.storyBeats = storyBeats
        self.detectedFramingMode = detectedFramingMode
        self.webcamCorner = webcamCorner
    }

    /// Duración neta restando los segmentos descartados
    public var netDuration: Double {
        if let beats = storyBeats, !beats.isEmpty {
            return beats.reduce(0.0) { $0 + $1.duration }
        }
        let total = timeRange.duration
        let cuts = cutSegments.reduce(0.0) { sum, seg in
            sum + max(0, seg.end - seg.start)
        }
        return max(0, total - cuts)
    }
}

public struct EDLResponse: Codable {
    public let status: String
    public let clips: [ClipDecision]
    public let message: String?

    public init(status: String, clips: [ClipDecision], message: String? = nil) {
        self.status = status
        self.clips = clips
        self.message = message
    }
}

// MARK: - Framing por clip (FIX-feed: cada clip con su propio encuadre)

/// Centro de encuadre de un tramo en tiempo-source.
public struct BeatCenter: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let x: CGFloat
    public let y: CGFloat
    public let faceWidth: CGFloat?

    public init(start: Double, end: Double, x: CGFloat, y: CGFloat, faceWidth: CGFloat? = nil) {
        self.start = start
        self.end = end
        self.x = x
        self.y = y
        self.faceWidth = faceWidth
    }
}

/// Framing resuelto para un clip: modo + centro global + centros por beat.
public struct ClipFraming: Equatable, Sendable {
    public var mode: FramingMode
    public var centerX: CGFloat
    public var centerY: CGFloat
    public var faceWidth: CGFloat?
    public var beatCenters: [BeatCenter]

    public init(mode: FramingMode, centerX: CGFloat, centerY: CGFloat, faceWidth: CGFloat? = nil, beatCenters: [BeatCenter] = []) {
        self.mode = mode
        self.centerX = centerX
        self.centerY = centerY
        self.faceWidth = faceWidth
        self.beatCenters = beatCenters
    }

    public static var fallback: ClipFraming {
        ClipFraming(mode: .autoFaceTrack, centerX: 0.5, centerY: 0.5)
    }
}

// MARK: - Editor Configuration Enums

public enum FramingMode: String, CaseIterable, Identifiable, Sendable {
    case autoFaceTrack = "Auto Face-Track"
    case splitScreen = "Split-Screen"
    case blurredBackground = "Fondo Borroso"
    case manualCrop = "Manual Crop"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .autoFaceTrack: return "person.crop.rectangle.badge.waveform"
        case .splitScreen: return "rectangle.split.2x1"
        case .blurredBackground: return "sparkles.rectangle.stack"
        case .manualCrop: return "crop"
        }
    }
}

public enum WebcamCorner: String, CaseIterable, Identifiable {
    case bottomRight = "Inferior Derecha"
    case bottomLeft = "Inferior Izquierda"
    case topRight = "Superior Derecha"
    case topLeft = "Superior Izquierda"
    case center = "Centro"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .bottomRight: return "arrow.down.right.square.fill"
        case .bottomLeft: return "arrow.down.left.square.fill"
        case .topRight: return "arrow.up.right.square.fill"
        case .topLeft: return "arrow.up.left.square.fill"
        case .center: return "dot.square.fill"
        }
    }

    public var centerNormalized: (x: CGFloat, y: CGFloat) {
        switch self {
        case .bottomRight: return (0.85, 0.80)
        case .bottomLeft: return (0.15, 0.80)
        case .topRight: return (0.85, 0.20)
        case .topLeft: return (0.15, 0.20)
        case .center: return (0.50, 0.50)
        }
    }
}

public enum SubtitleStyle: String, CaseIterable, Identifiable {
    case hormozi = "Hormozi Punch"
    case minimalDark = "Minimal Dark"
    case karaoke = "Karaoke"

    public var id: String { rawValue }

    public var previewDescription: String {
        switch self {
        case .hormozi: return "BOLD • POP SPRING • NEÓN"
        case .minimalDark: return "Limpio • Cápsula traslúcida"
        case .karaoke: return "Llenado continuo progresivo"
        }
    }
}

public enum SubtitleFontSize: String, CaseIterable, Identifiable {
    case small = "S"
    case medium = "M"
    case large = "L"

    public var id: String { rawValue }

    public var pointSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 17
        case .large: return 20
        }
    }
}

public struct LutPresetItem: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let thumbnailColor: String
    public let contrast: Double
    public let saturation: Double
    public let warmth: Double
    public let cubeFilterName: String?

    public init(
        id: String,
        name: String,
        description: String,
        thumbnailColor: String,
        contrast: Double,
        saturation: Double,
        warmth: Double,
        cubeFilterName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailColor = thumbnailColor
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.cubeFilterName = cubeFilterName
    }
}

import SwiftUI

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

