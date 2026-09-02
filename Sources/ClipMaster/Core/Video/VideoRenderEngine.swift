import Foundation
import AVFoundation
import CoreGraphics
import QuartzCore
#if canImport(Photos)
import Photos
#endif

public enum RenderError: Error, LocalizedError {
    case noVideoTrack
    case compositionFailed(String)
    case exportSessionCreationFailed
    case exportFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "El video seleccionado no contiene una pista de video válida."
        case .compositionFailed(let msg):
            return "Fallo al crear la composición de video: \(msg)"
        case .exportSessionCreationFailed:
            return "No se pudo inicializar la sesión de exportación de AVFoundation."
        case .exportFailed(let msg):
            return "Error durante el renderizado del video: \(msg)"
        case .cancelled:
            return "La exportación fue cancelada."
        }
    }
}

public struct RenderConfiguration {
    public var clip: ClipDecision
    public var framingMode: FramingMode
    public var subtitleStyle: SubtitleStyle
    public var words: [WordTimestamp]
    public var musicTrackURL: URL?
    public var enableAutoDucking: Bool
    public var subtitleVerticalPosition: CGFloat
    public var speakerCenterX: CGFloat
    public var speakerCenterY: CGFloat
    public var outputSize: CGSize

    public init(
        clip: ClipDecision,
        framingMode: FramingMode = .autoFaceTrack,
        subtitleStyle: SubtitleStyle = .hormozi,
        words: [WordTimestamp],
        musicTrackURL: URL? = nil,
        enableAutoDucking: Bool = true,
        subtitleVerticalPosition: CGFloat = 0.65,
        speakerCenterX: CGFloat = 0.5,
        speakerCenterY: CGFloat = 0.5,
        outputSize: CGSize = CGSize(width: 1080, height: 1920)
    ) {
        self.clip = clip
        self.framingMode = framingMode
        self.subtitleStyle = subtitleStyle
        self.words = words
        self.musicTrackURL = musicTrackURL
        self.enableAutoDucking = enableAutoDucking
        self.subtitleVerticalPosition = subtitleVerticalPosition
        self.speakerCenterX = speakerCenterX
        self.speakerCenterY = speakerCenterY
        self.outputSize = outputSize
    }
}

/// Motor principal de composición, ensamblado de cortes y renderizado final de video en 9:16
public final class VideoRenderEngine {
    public static let shared = VideoRenderEngine()

    public init() {}

    /// Calcula la lista de rangos temporales continuos [start, end] que deben conservarse
    public func calculateKeepSegments(
        totalRange: TimeRange,
        cutSegments: [CutSegment]
    ) -> [(start: Double, end: Double)] {
        // Ordenar cortes cronológicamente
        let sortedCuts = cutSegments
            .filter { $0.start >= totalRange.start && $0.end <= totalRange.end }
            .sorted(by: { $0.start < $1.start })

        var keepSegments: [(start: Double, end: Double)] = []
        var cursor = totalRange.start

        for cut in sortedCuts {
            if cut.start > cursor {
                keepSegments.append((start: cursor, end: cut.start))
            }
            cursor = max(cursor, cut.end)
        }

        if cursor < totalRange.end {
            keepSegments.append((start: cursor, end: totalRange.end))
        }

        return keepSegments
    }

    public func calculateKeepSegments(for clip: ClipDecision) -> [(start: Double, end: Double)] {
        if let beats = clip.storyBeats, !beats.isEmpty {
            return beats.map { (start: $0.start, end: $0.end) }
        }
        return calculateKeepSegments(totalRange: clip.timeRange, cutSegments: clip.cutSegments)
    }

    /// Ensambla la composición AVMutableComposition y la exporta a un archivo de video 9:16 a 1080x1920
    public func renderAndExport(
        sourceAsset: AVAsset,
        config: RenderConfiguration,
        outputURL: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        // 1. Preparar composición multipista
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderError.compositionFailed("No se pudo crear pista de video en composición")
        }

        let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw RenderError.noVideoTrack
        }

        let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first

        // 2. Concatenar los segmentos válidos (storyBeats o keepSegments)
        let keepSegments = calculateKeepSegments(for: config.clip)

        var insertionTime = CMTime.zero
        var speechIntervals: [DuckingSpeechInterval] = []

        for segment in keepSegments {
            let segDuration = segment.end - segment.start
            guard segDuration > 0.05 else { continue }

            let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
            let duration = CMTime(seconds: segDuration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            // Insertar video
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertionTime)

            // Insertar audio original del hablante
            if let audioTrack = sourceAudioTrack {
                try compAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: insertionTime)
            }

            // Registrar intervalo de habla para Auto-Ducking
            let segEndTime = CMTimeAdd(insertionTime, duration)
            speechIntervals.append(DuckingSpeechInterval(start: insertionTime, end: segEndTime))

            insertionTime = segEndTime
        }

        let totalDuration = insertionTime
        guard totalDuration.seconds > 0 else {
            throw RenderError.compositionFailed("La duración de la composición es cero")
        }

        // 3. Pista de música secundaria y Auto-Ducking (si aplica)
        var audioMix: AVAudioMix? = nil
        if let musicURL = config.musicTrackURL, config.enableAutoDucking {
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicAudioTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first,
               let compMusicTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                // Rellenar la música en bucle si es necesario
                var musicInsertionTime = CMTime.zero
                let musicDuration = try await musicAsset.load(.duration)

                while musicInsertionTime < totalDuration {
                    let chunkDuration = min(musicDuration, CMTimeSubtract(totalDuration, musicInsertionTime))
                    try compMusicTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: chunkDuration),
                        of: musicAudioTrack,
                        at: musicInsertionTime
                    )
                    musicInsertionTime = CMTimeAdd(musicInsertionTime, chunkDuration)
                }

                audioMix = AudioDuckingEngine.shared.createDuckingAudioMix(
                    musicTrack: compMusicTrack,
                    speechIntervals: speechIntervals,
                    totalDuration: totalDuration
                )
            }
        }

        // 4. Configurar VideoComposition (Recorte 9:16 y Capa de Subtítulos)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = config.outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        let sourceDimensions = try await sourceVideoTrack.load(.naturalSize)

        // Calcular encuadre centrado o con face-tracking
        let cropTransform = FaceTrackingService.shared.calculateCropTransform(
            originalSize: sourceDimensions,
            targetSize: config.outputSize,
            centerX: config.speakerCenterX,
            centerY: config.speakerCenterY,
            mode: config.framingMode
        )
        layerInstruction.setTransform(cropTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // 5. Capa de subtítulos dinámicos con CoreAnimation
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: config.outputSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: config.outputSize)
        parentLayer.addSublayer(videoLayer)

        let subtitleLayer = SubtitleOverlayGenerator.shared.createSubtitleLayer(
            words: config.words,
            highlightWords: config.clip.highlightWords,
            style: config.subtitleStyle,
            renderSize: config.outputSize,
            verticalPositionRatio: config.subtitleVerticalPosition
        )
        parentLayer.addSublayer(subtitleLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // 6. Exportar con AVAssetExportSession
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RenderError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                progress?(Double(exportSession.progress))
            }
        }

        await exportSession.export()
        progressTask.cancel()

        if exportSession.status == .completed {
            progress?(1.0)
        } else if exportSession.status == .cancelled {
            throw RenderError.cancelled
        } else {
            throw RenderError.exportFailed(exportSession.error?.localizedDescription ?? "Error desconocido en exportación")
        }
    }
}
