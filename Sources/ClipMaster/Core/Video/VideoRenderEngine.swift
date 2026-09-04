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
    public var subtitleVerticalPosition: CGFloat
    public var speakerCenterX: CGFloat
    public var speakerCenterY: CGFloat
    /// Ancho normalizado del rostro (0...1) para zoom adaptativo. nil = sin zoom.
    public var speakerFaceWidth: CGFloat?
    /// F5: encuadre por tramo en tiempo-source. Si se provee y el modo es autoFaceTrack,
    /// cada segmento de la composición usa su propio centro (corte duro en los jump cuts,
    /// que es lo natural). Si es nil se usa el centro único legacy.
    public var perBeatCenters: [(start: Double, end: Double, x: CGFloat, y: CGFloat, faceWidth: CGFloat?)]?
    public var outputSize: CGSize

    public init(
        clip: ClipDecision,
        framingMode: FramingMode = .autoFaceTrack,
        subtitleStyle: SubtitleStyle = .hormozi,
        words: [WordTimestamp],
        subtitleVerticalPosition: CGFloat = 0.65,
        speakerCenterX: CGFloat = 0.5,
        speakerCenterY: CGFloat = 0.5,
        speakerFaceWidth: CGFloat? = nil,
        perBeatCenters: [(start: Double, end: Double, x: CGFloat, y: CGFloat, faceWidth: CGFloat?)]? = nil,
        outputSize: CGSize = CGSize(width: 1080, height: 1920)
    ) {
        self.clip = clip
        self.framingMode = framingMode
        self.subtitleStyle = subtitleStyle
        self.words = words
        self.subtitleVerticalPosition = subtitleVerticalPosition
        self.speakerCenterX = speakerCenterX
        self.speakerCenterY = speakerCenterY
        self.speakerFaceWidth = speakerFaceWidth
        self.perBeatCenters = perBeatCenters
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

        var compVideoTrack2: AVMutableCompositionTrack? = nil
        if config.framingMode == .splitScreen {
            compVideoTrack2 = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw RenderError.noVideoTrack
        }

        let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first

        // 2. Concatenar los segmentos válidos (storyBeats o keepSegments)
        let keepSegments = calculateKeepSegments(for: config.clip)
        let sourceDuration = (try? await sourceAsset.load(.duration).seconds) ?? .infinity
        // Segmentos clampeados al EOF real (misma lista para inserción y transforms)
        let clampedSegments: [(start: Double, end: Double)] = keepSegments.compactMap { seg in
            let s = max(0, min(seg.start, sourceDuration))
            let e = max(0, min(seg.end, sourceDuration))
            guard e - s > 0.05 else {
                print("⚠️ [Render] segmento fuera de rango, saltado: \(seg.start)-\(seg.end)")
                return nil
            }
            return (s, e)
        }

        var insertionTime = CMTime.zero
        for segment in clampedSegments {
            let segDuration = segment.end - segment.start

            let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
            let duration = CMTime(seconds: segDuration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            // Insertar video en pista principal y pista secundaria para split-screen
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertionTime)
            try compVideoTrack2?.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertionTime)

            // Insertar audio original del hablante
            if let audioTrack = sourceAudioTrack {
                try compAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: insertionTime)
            }

            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        let totalDuration = insertionTime
        guard totalDuration.seconds > 0 else {
            throw RenderError.compositionFailed("La duración de la composición es cero")
        }

        // 3. Configurar VideoComposition (Recorte 9:16 y Capa de Subtítulos)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = config.outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        let rawSize = try await sourceVideoTrack.load(.naturalSize)
        let rawTransform = (try? await sourceVideoTrack.load(.preferredTransform)) ?? .identity
        let sourceDimensions = FaceCropCalculator.orientedSize(naturalSize: rawSize, preferredTransform: rawTransform)

        if config.framingMode == .splitScreen, let track2 = compVideoTrack2 {
            let split = FaceCropCalculator.splitFraction
            let topHeight = config.outputSize.height * split
            let bottomHeight = config.outputSize.height - topHeight

            // Track 1: pantalla ajustada al ancho, PEGADA ARRIBA (sin banda negra superior)
            let topScale = config.outputSize.width / sourceDimensions.width

            var topTransform = CGAffineTransform.identity
            topTransform = topTransform.scaledBy(x: topScale, y: topScale)

            let layerInstruction1 = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
            layerInstruction1.setTransform(rawTransform.concatenating(topTransform), at: .zero)

            // Track 2: webcam con crop del MISMO aspect de su zona -> la llena exacta
            let zoneAspect = config.outputSize.width / bottomHeight
            let cropRect = FaceCropCalculator.splitBottomCropRect(
                sourceSize: sourceDimensions,
                center: CGPoint(x: config.speakerCenterX, y: config.speakerCenterY),
                targetAspect: zoneAspect
            )
            let cropX = cropRect.origin.x
            let cropY = cropRect.origin.y
            let cropW = cropRect.width
            let cropH = cropRect.height

            let bottomScale = config.outputSize.width / cropW
            var bottomTransform = CGAffineTransform.identity
            bottomTransform = bottomTransform.translatedBy(x: 0, y: topHeight)
            bottomTransform = bottomTransform.scaledBy(x: bottomScale, y: bottomScale)
            bottomTransform = bottomTransform.translatedBy(x: -cropX, y: -cropY)

            let layerInstruction2 = AVMutableVideoCompositionLayerInstruction(assetTrack: track2)
            layerInstruction2.setTransform(rawTransform.concatenating(bottomTransform), at: .zero)
            layerInstruction2.setCropRectangle(
                CGRect(x: cropX, y: cropY, width: cropW, height: cropH),
                at: .zero
            )

            instruction.layerInstructions = [layerInstruction1, layerInstruction2]
        } else {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
            // F4: misma matemática que el preview (FaceCropCalculator)
            // F5: un transform por segmento de composición cuando hay centros por beat
            if config.framingMode == .autoFaceTrack, let perBeat = config.perBeatCenters, !perBeat.isEmpty {
                var compCursor = CMTime.zero
                struct ScheduledItem {
                    let time: CMTime
                    let transform: CGAffineTransform
                    let center: CGPoint
                    let isBeatBoundary: Bool
                }
                var scheduled: [ScheduledItem] = []
                for segment in clampedSegments {
                    let segDuration = segment.end - segment.start
                    guard segDuration > 0.05 else { continue }
                    // Buscar centros de beat o sub-tomas que intersecten este segmento
                    let matching = perBeat.filter { $0.end > segment.start + 0.05 && $0.start < segment.end - 0.05 }
                        .sorted(by: { $0.start < $1.start })

                    if matching.count > 1 {
                        var isFirstSub = true
                        for sub in matching {
                            let subStart = max(segment.start, sub.start)
                            let subEnd = min(segment.end, sub.end)
                            guard subEnd - subStart > 0.05 else { continue }
                            let offsetInSeg = subStart - segment.start
                            let transformTime = CMTimeAdd(compCursor, CMTime(seconds: offsetInSeg, preferredTimescale: 600))
                            let t = FaceCropCalculator.exportTransform(
                                sourceSize: sourceDimensions,
                                targetSize: config.outputSize,
                                center: CGPoint(x: sub.x, y: sub.y),
                                faceWidth: sub.faceWidth,
                                mode: config.framingMode
                            )
                            scheduled.append(ScheduledItem(
                                time: transformTime,
                                transform: rawTransform.concatenating(t),
                                center: CGPoint(x: sub.x, y: sub.y),
                                isBeatBoundary: isFirstSub
                            ))
                            isFirstSub = false
                        }
                    } else {
                        let mid = (segment.start + segment.end) / 2.0
                        let beat = matching.first ?? perBeat.first(where: { mid >= $0.start && mid <= $0.end })
                        let cx = beat?.x ?? config.speakerCenterX
                        let cy = beat?.y ?? config.speakerCenterY
                        let fw = beat?.faceWidth ?? config.speakerFaceWidth
                        let t = FaceCropCalculator.exportTransform(
                            sourceSize: sourceDimensions,
                            targetSize: config.outputSize,
                            center: CGPoint(x: cx, y: cy),
                            faceWidth: fw,
                            mode: config.framingMode
                        )
                        scheduled.append(ScheduledItem(
                            time: compCursor,
                            transform: rawTransform.concatenating(t),
                            center: CGPoint(x: cx, y: cy),
                            isBeatBoundary: true
                        ))
                    }
                    compCursor = CMTimeAdd(compCursor, CMTime(seconds: segDuration, preferredTimescale: 600))
                }

                // Programar transforms: limitar transiciones Whip Slide a cambios reales de toma o saltos narrativos espaciados
                // Slide to right: video saliente se desliza hacia la derecha (+X), entrante entra desde la izquierda (-X)
                let slidePush = config.outputSize.width * 0.12 // Sutil y estilizado (12% del ancho)
                let pushRight = CGAffineTransform(translationX: slidePush, y: 0)
                let pushLeft = CGAffineTransform(translationX: -slidePush, y: 0)
                let rampSec: Double = 0.04 // 40ms antes y 40ms después (80ms total, rápido y punchy)

                var lastTransitionTime: Double = -10.0 // Cooldown de transiciones

                for i in 0 ..< scheduled.count {
                    let item = scheduled[i]
                    if i == 0 || item.time.seconds < 0.1 {
                        layerInstruction.setTransform(item.transform, at: item.time)
                    } else {
                        let prev = scheduled[i - 1]
                        let cutTime = item.time
                        let centerDiff = hypot(item.center.x - prev.center.x, item.center.y - prev.center.y)
                        let timeSinceLast = cutTime.seconds - lastTransitionTime

                        // Condición de transición:
                        // 1. Cambio real de toma/encuadre (ej: webcam a cara completa o viceversa, centerDiff >= 0.16)
                        // 2. O salto de beat con cooldown >= 4.0s y ligero cambio visual (centerDiff >= 0.06)
                        let isShotChange = centerDiff >= 0.16
                        let isSpacedBeat = item.isBeatBoundary && centerDiff >= 0.06 && timeSinceLast >= 4.0
                        let shouldTransition = (isShotChange || isSpacedBeat) && timeSinceLast >= 2.0

                        if shouldTransition {
                            let rampDur = CMTime(seconds: rampSec, preferredTimescale: 600)
                            let rampStart = CMTimeSubtract(cutTime, rampDur)

                            // 1. Fase de salida (pre-corte): la toma anterior se desliza rápidamente hacia la derecha
                            if rampStart > prev.time {
                                layerInstruction.setTransformRamp(
                                    fromStart: prev.transform,
                                    toEnd: prev.transform.concatenating(pushRight),
                                    timeRange: CMTimeRange(start: rampStart, duration: rampDur)
                                )
                            }

                            // 2. Fase de entrada (post-corte): la nueva toma entra desde la izquierda (-push) y se asienta
                            layerInstruction.setTransformRamp(
                                fromStart: item.transform.concatenating(pushLeft),
                                toEnd: item.transform,
                                timeRange: CMTimeRange(start: cutTime, duration: rampDur)
                            )

                            // 3. Fijar el transform firme una vez terminada la rampa
                            let settleTime = CMTimeAdd(cutTime, rampDur)
                            layerInstruction.setTransform(item.transform, at: settleTime)
                            lastTransitionTime = cutTime.seconds
                        } else {
                            // Corte directo limpio: sin animación en micro-cortes para evitar mareos
                            layerInstruction.setTransform(item.transform, at: cutTime)
                        }
                    }
                }
            } else {
                let cropTransform = FaceCropCalculator.exportTransform(
                    sourceSize: sourceDimensions,
                    targetSize: config.outputSize,
                    center: CGPoint(x: config.speakerCenterX, y: config.speakerCenterY),
                    faceWidth: config.speakerFaceWidth,
                    mode: config.framingMode
                )
                layerInstruction.setTransform(rawTransform.concatenating(cropTransform), at: .zero)
            }
            instruction.layerInstructions = [layerInstruction]
        }

        videoComposition.instructions = [instruction]

        // 5. Capa de subtítulos dinámicos con CoreAnimation
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: config.outputSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: config.outputSize)
        parentLayer.isGeometryFlipped = true
        videoLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)

        if config.framingMode == .splitScreen {
            let divider = CALayer()
            divider.frame = CGRect(
                x: 0,
                y: config.outputSize.height * 0.55 - 2,
                width: config.outputSize.width,
                height: 4
            )
            divider.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 0.95)
            parentLayer.addSublayer(divider)
        }

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
