import Foundation
import AVFoundation
import Vision
import CoreGraphics

public enum SceneType: Equatable {
    case fullScreenSpeaker(faceRect: CGRect)
    case splitScreen(webcamRect: CGRect)
    case fullScreenContent

    public var title: String {
        switch self {
        case .fullScreenSpeaker: return "Hablante a Cámara"
        case .splitScreen: return "Split-Screen (Pantalla + Cara)"
        case .fullScreenContent: return "Pantalla Completa"
        }
    }
}

public struct SplitScreenTransforms {
    public let topScreenTransform: CGAffineTransform
    public let bottomSpeakerTransform: CGAffineTransform

    public init(topScreenTransform: CGAffineTransform, bottomSpeakerTransform: CGAffineTransform) {
        self.topScreenTransform = topScreenTransform
        self.bottomSpeakerTransform = bottomSpeakerTransform
    }
}

/// Motor de clasificación visual inteligente y cálculo de transformaciones Split-Screen usando Apple Vision
public final class SceneLayoutEngine {
    public static let shared = SceneLayoutEngine()

    private init() {}

    // MARK: - Clasificación de Escena de un Fotograma
    public func classifyFrame(cgImage: CGImage) -> SceneType {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        try? handler.perform([request])
        guard let results = request.results, !results.isEmpty else {
            return .fullScreenContent
        }

        // Ordenar por tamaño de rostro decreciente
        let sortedFaces = results.sorted { ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height) }
        guard let primaryFace = sortedFaces.first else {
            return .fullScreenContent
        }

        let face = primaryFace.boundingBox

        // Si la cara es grande (> 14% de la altura del video) -> Hablante principal
        if face.height >= 0.14 {
            return .fullScreenSpeaker(faceRect: face)
        }

        // Si la cara es pequeña (3% a 12%) y está desplazada hacia una esquina o lateral -> Webcam en pantalla compartida
        let isNearEdge = (face.midX > 0.55 || face.midX < 0.45) || (face.midY < 0.45 || face.midY > 0.65)
        if face.height >= 0.03 && face.height < 0.14 && isNearEdge {
            return .splitScreen(webcamRect: face)
        }

        // Por defecto, si hay una cara pequeña pero no identificada como webcam clara, centrar en la cara
        return .fullScreenSpeaker(faceRect: face)
    }

    // MARK: - Resolución conjunta editorial-visual (F5)
    public struct ResolvedFraming: Equatable {
        public let mode: FramingMode
        public let centerX: CGFloat
        public let centerY: CGFloat
        public let faceWidth: CGFloat?
        public let reason: String

        public init(mode: FramingMode, centerX: CGFloat, centerY: CGFloat, faceWidth: CGFloat?, reason: String) {
            self.mode = mode
            self.centerX = centerX
            self.centerY = centerY
            self.faceWidth = faceWidth
            self.reason = reason
        }
    }

    /// Decide el encuadre del clip combinando lo que pide el backend (`needsFace`
    /// del hook) con lo que vio Vision (confianza, PiP, multi-speaker).
    /// El centro se toma del MEJOR track con cara (no necesariamente el hook).
    /// Función pura para poder testearla sin video.
    public func resolveClipFraming(
        hookNeedsFace: Bool,
        hookTrack: BeatFaceTrack?,
        allTracks: [BeatFaceTrack]? = nil,
        anyScreenShare: Bool,
        anyMultiSpeaker: Bool
    ) -> ResolvedFraming {
        let tracks = allTracks ?? (hookTrack.map { [$0] } ?? [])
        // Mejor track con cara (no necesariamente el hook): más confianza×detección.
        // Si el hook no tiene cara pero otro beat sí, se centra en esa.
        let bestFaceTrack = tracks
            .filter { $0.averageFace != nil }
            .max(by: { ($0.confidence * Float($0.detectionRate)) < ($1.confidence * Float($1.detectionRate)) })
        // 1. Multi-speaker (entrevista/podcast): no perseguir una cara, plano abierto al centro
        if anyMultiSpeaker {
            return ResolvedFraming(mode: .autoFaceTrack, centerX: 0.5, centerY: 0.5, faceWidth: nil,
                reason: "multi_speaker_centro_abierto")
        }
        // 2. Webcam PiP en algún beat: split-screen para no perder ni pantalla ni cara
        if anyScreenShare, let track = bestFaceTrack ?? hookTrack, let face = track.averageFace {
            return ResolvedFraming(mode: .splitScreen, centerX: face.midX, centerY: face.midY, faceWidth: face.width,
                reason: "screenshare_split")
        }
        // 3. Hay cara fiable en algún beat: seguirla (aunque el hook no la tenga)
        if let track = bestFaceTrack, track.confidence >= 0.3, track.detectionRate >= 0.25 {
            return ResolvedFraming(mode: .autoFaceTrack, centerX: track.averageFace!.midX, centerY: track.averageFace!.midY, faceWidth: track.averageFace!.width,
                reason: "mejor_beat_con_cara")
        }
        // 4. El hook necesita cara pero no hay detección fiable: no decapitar,
        // fondo completo al centro para que se lea el contenido
        if hookNeedsFace {
            return ResolvedFraming(mode: .blurredBackground, centerX: 0.5, centerY: 0.5, faceWidth: nil,
                reason: "hook_sin_cara_fondo_completo")
        }
        // 5. Sin requerimiento facial: cara si la hay, si no centro
        if let track = bestFaceTrack, let face = track.averageFace {
            return ResolvedFraming(mode: .autoFaceTrack, centerX: face.midX, centerY: face.midY, faceWidth: face.width,
                reason: "cara_disponible")
        }
        return ResolvedFraming(mode: .autoFaceTrack, centerX: 0.5, centerY: 0.5, faceWidth: nil,
            reason: "fallback_centro")
    }

    // MARK: - Muestreo y Clasificación de Escenas a lo largo de un Clip
    public func analyzeClipScenes(asset: AVAsset, for clip: ClipDecision) async -> [String: SceneType] {
        var results: [String: SceneType] = [:]
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 640, height: 360) // Baja resolución para procesamiento ultrarrápido

        let segments = clip.storyBeats?.map { TimeRange(start: $0.start, end: $0.end) } ?? [clip.timeRange]

        for (index, segment) in segments.enumerated() {
            let midTime = CMTime(seconds: (segment.start + segment.end) / 2.0, preferredTimescale: 600)
            if let imageRef = try? imageGenerator.copyCGImage(at: midTime, actualTime: nil) {
                let scene = classifyFrame(cgImage: imageRef)
                results["beat_\(index)"] = scene
            } else {
                results["beat_\(index)"] = .fullScreenSpeaker(faceRect: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3))
            }
        }

        return results
    }

    // MARK: - Cálculo de Matrices de Transformación para Split-Screen
    /// Genera la transformación para la mitad superior (pantalla compartida) y la mitad inferior (webcam con zoom centrado)
    public func calculateSplitScreenTransforms(
        sourceSize: CGSize,
        targetSize: CGSize = CGSize(width: 1080, height: 1920),
        webcamNormRect: CGRect? = nil
    ) -> SplitScreenTransforms {
        // En 9:16 (1080x1920):
        // Mitad Superior: 1080 de ancho x 1056 de alto (~55% de la pantalla)
        // Mitad Inferior: 1080 de ancho x 864 de alto (~45% de la pantalla)
        let topHeight: CGFloat = targetSize.height * 0.55
        let bottomHeight: CGFloat = targetSize.height * 0.45

        // 1. Transformación Superior: Contenido de la Pantalla (Escalar ancho y centrar verticalmente en la zona superior)
        let topScale = targetSize.width / sourceSize.width
        let topScaledHeight = sourceSize.height * topScale
        let topOffsetY = (topHeight - topScaledHeight) / 2.0

        var topTransform = CGAffineTransform.identity
        topTransform = topTransform.scaledBy(x: topScale, y: topScale)
        topTransform = topTransform.translatedBy(x: 0, y: topOffsetY / topScale)

        // 2. Transformación Inferior: Webcam Aumentada y Centrada
        let faceBox = webcamNormRect ?? CGRect(x: 0.85, y: 0.80, width: 0.22, height: 0.22)
        
        let faceCenterX = faceBox.midX * sourceSize.width
        let faceCenterY = faceBox.midY * sourceSize.height

        let bottomScale = (targetSize.width / (sourceSize.width * max(0.18, faceBox.width))) * 1.15

        let targetCenterX = targetSize.width / 2.0
        let targetCenterY = topHeight + (bottomHeight / 2.0)

        var bottomTransform = CGAffineTransform.identity
        bottomTransform = bottomTransform.translatedBy(x: targetCenterX, y: targetCenterY)
        bottomTransform = bottomTransform.scaledBy(x: bottomScale, y: bottomScale)
        bottomTransform = bottomTransform.translatedBy(x: -faceCenterX, y: -faceCenterY)

        return SplitScreenTransforms(
            topScreenTransform: topTransform,
            bottomSpeakerTransform: bottomTransform
        )
    }
}
