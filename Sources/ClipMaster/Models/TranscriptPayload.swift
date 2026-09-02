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

public struct TranscriptPayload: Codable {
    public let videoId: String
    public let language: String?
    public let videoDuration: Double
    public var words: [WordTimestamp]

    public init(
        videoId: String,
        language: String? = nil,
        videoDuration: Double,
        words: [WordTimestamp]
    ) {
        self.videoId = videoId
        self.language = language
        self.videoDuration = videoDuration
        self.words = words
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

    public init(start: Double, end: Double, role: String, text: String) {
        self.start = start
        self.end = end
        self.role = role
        self.text = text
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

    public init(
        id: String,
        title: String,
        viralScore: Int,
        hook: String,
        timeRange: TimeRange,
        cutSegments: [CutSegment],
        highlightWords: [HighlightWord],
        storyBeats: [StoryBeat]? = nil
    ) {
        self.id = id
        self.title = title
        self.viralScore = viralScore
        self.hook = hook
        self.timeRange = timeRange
        self.cutSegments = cutSegments
        self.highlightWords = highlightWords
        self.storyBeats = storyBeats
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

// MARK: - Editor Configuration Enums

public enum FramingMode: String, CaseIterable, Identifiable {
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
        case .small: return 22
        case .medium: return 28
        case .large: return 36
        }
    }
}

public struct MusicTrackItem: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let genre: String
    public let bpm: Int
    public let duration: Int
    public let previewUrl: String
    public let duckingVoiceDb: Double
    public let duckingMusicDb: Double

    public init(
        id: String,
        title: String,
        genre: String,
        bpm: Int,
        duration: Int,
        previewUrl: String,
        duckingVoiceDb: Double = 0.0,
        duckingMusicDb: Double = -18.0
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.bpm = bpm
        self.duration = duration
        self.previewUrl = previewUrl
        self.duckingVoiceDb = duckingVoiceDb
        self.duckingMusicDb = duckingMusicDb
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
