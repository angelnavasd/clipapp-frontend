import Foundation
import CoreGraphics

// MARK: - Modelos espejo del backend (analyze-frames.dto.ts)

public enum FrameScene: String, Codable, Sendable {
    case talking_head
    case screen_share
    case pip
    case multi_speaker
    case no_person
    case unclear
}

public enum SpeakerZone: String, Codable, Sendable {
    case left
    case center
    case right
    case fullscreen
    case none
}

public enum PipCorner: String, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case none
}

public struct FrameInput: Codable, Sendable {
    public let id: String
    public let timestamp: Double
    public let clipId: String?
    public let beatId: String?
    public let role: String?
    public let imageBase64: String

    public init(id: String, timestamp: Double, clipId: String? = nil, beatId: String? = nil, role: String? = nil, imageBase64: String) {
        self.id = id
        self.timestamp = timestamp
        self.clipId = clipId
        self.beatId = beatId
        self.role = role
        self.imageBase64 = imageBase64
    }
}

public struct FrameAnalysis: Codable, Equatable, Sendable {
    public let id: String
    public let scene: FrameScene
    public let speakerZone: SpeakerZone
    public let pipCorner: PipCorner
    public let confidence: Double
    /// Centro X grueso 0-100 de la cara/ventanita (-1 si no hay persona).
    public let faceX: Double?
    /// Centro Y grueso 0-100 de la CARA (-1 si no hay persona).
    public let faceY: Double?
    /// Ancho grueso de la CARA en % del ancho (-1 si no hay persona).
    public let faceW: Double?

    public init(id: String, scene: FrameScene, speakerZone: SpeakerZone, pipCorner: PipCorner, confidence: Double, faceX: Double? = nil, faceY: Double? = nil, faceW: Double? = nil) {
        self.id = id
        self.scene = scene
        self.speakerZone = speakerZone
        self.pipCorner = pipCorner
        self.confidence = confidence
        self.faceX = faceX
        self.faceY = faceY
        self.faceW = faceW
    }

    /// Centro X normalizado: faceX si viene válido, si no el tercio.
    public var centerX: CGFloat {
        if let fx = faceX, fx >= 0, fx <= 100 { return CGFloat(fx) / 100.0 }
        return FrameFramingMapper.x(for: speakerZone)
    }

    /// Centro Y normalizado: faceY si viene válido, si no 0.45 (tercio superior).
    public var centerY: CGFloat {
        if let fy = faceY, fy >= 0, fy <= 100 { return CGFloat(fy) / 100.0 }
        return 0.45
    }

    /// Ancho de cara normalizado para la ventana adaptativa (nil = frame completo).
    public var faceWidthNorm: CGFloat? {
        if let fw = faceW, fw > 0, fw <= 100 { return CGFloat(fw) / 100.0 }
        return nil
    }

    /// ¿Hay persona localizable en este frame?
    public var hasPerson: Bool {
        scene == .talking_head || scene == .pip || scene == .multi_speaker
    }
}

public struct FramesResponse: Codable {
    public let status: String
    public let frames: [FrameAnalysis]
}

// MARK: - Mapper puro: análisis Gemini -> encuadre (testeable sin red ni video)

/// Convierte la clasificación de Gemini en framing. Reglas intencionalmente
/// gruesas (tercios, sin zoom): la precisión de un VLM no da para píxeles,
/// pero sobra para "dónde está la persona / hay pantalla o no".
public enum FrameFramingMapper {
    /// Confianza mínima para creerle a un frame. Debajo: default seguro.
    public static var minConfidence: Double = 0.4

    public struct Resolved: Equatable {
        public let mode: FramingMode
        public let x: CGFloat
        public let y: CGFloat
        public let faceWidth: CGFloat?
        public let reason: String
    }

    public static var safeDefault: Resolved {
        Resolved(mode: .autoFaceTrack, x: 0.5, y: 0.45, faceWidth: nil, reason: "gemini_default_centro")
    }

    /// Un thumb -> framing. REGLA ÚNICA: siempre la cara.
    /// Da igual si es talking, PiP o multi: el crop 9:16 se centra en la cara con
    /// ventana adaptativa a su tamaño. La pantalla se ignora por diseño (da más
    /// problemas que valor en 9:16). Sin persona: centro neutro.
    public static func framing(for frame: FrameAnalysis) -> Resolved {
        guard frame.confidence >= minConfidence, frame.hasPerson else { return safeDefault }
        return Resolved(mode: .autoFaceTrack, x: frame.centerX, y: frame.centerY,
            faceWidth: frame.faceWidthNorm,
            reason: "gemini_cara_\(frame.scene.rawValue)")
    }

    /// Los 2 thumbs de un beat -> un BeatCenter en tiempo-source.
    /// Se usa el de mayor confianza; en empate se promedian los centros
    /// (suaviza el ruido grueso del VLM entre los dos thumbs).
    public static func beatCenter(start: Double, end: Double, frames: [FrameAnalysis]) -> BeatCenter {
        let usable = frames.filter { $0.confidence >= minConfidence && $0.hasPerson }
        guard !usable.isEmpty else {
            return BeatCenter(start: start, end: end, x: 0.5, y: 0.45)
        }
        let ranked = usable.sorted { $0.confidence > $1.confidence }
        let best = framing(for: ranked[0])
        if ranked.count > 1 {
            let second = framing(for: ranked[1])
            if abs(ranked[1].confidence - ranked[0].confidence) < 0.15 {
                let mx = (best.x + second.x) / 2.0
                let my = (best.y + second.y) / 2.0
                let mw = [best.faceWidth, second.faceWidth].compactMap { $0 }.max()
                return BeatCenter(start: start, end: end, x: mx, y: my, faceWidth: mw)
            }
        }
        return BeatCenter(start: start, end: end, x: best.x, y: best.y, faceWidth: best.faceWidth)
    }

    // MARK: - Helpers

    static func x(for zone: SpeakerZone) -> CGFloat {
        switch zone {
        case .left: return 0.25
        case .center: return 0.5
        case .right: return 0.75
        case .fullscreen, .none: return 0.5
        }
    }

    static func webcamCorner(for pip: PipCorner) -> WebcamCorner {
        switch pip {
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .none: return .bottomRight
        }
    }
}
