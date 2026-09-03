import Foundation
import Vision
import CoreGraphics
import AVFoundation

public struct FaceTrackingSample: Equatable {
    public let timestamp: Double
    public let boundingBox: CGRect // Coordenadas normalizadas [0, 1], origen arriba-izquierda
    public let smoothedCenterX: CGFloat
    public let smoothedCenterY: CGFloat

    public init(timestamp: Double, boundingBox: CGRect, smoothedCenterX: CGFloat, smoothedCenterY: CGFloat) {
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        self.smoothedCenterX = smoothedCenterX
        self.smoothedCenterY = smoothedCenterY
    }
}

public struct FaceDetection: Equatable {
    public let rect: CGRect
    public let confidence: Float

    public init(rect: CGRect, confidence: Float) {
        self.rect = rect
        self.confidence = confidence
    }
}

/// Resultado de tracking para un beat/storyBeat individual (base de F5: framing por beat)
public struct BeatFaceTrack: Equatable {
    public let beatIndex: Int
    public let start: Double
    public let end: Double
    public let samples: [FaceTrackingSample]
    public let averageFace: CGRect?
    /// Confianza media 0...1 de las detecciones del beat
    public let confidence: Float
    /// Máximo nº de rostros vistos en un frame del beat (para detectar multi-speaker)
    public let maxFaceCount: Int
    /// Fracción de frames con rostro (0...1)
    public let detectionRate: Double
    public let isScreenShare: Bool

    public init(
        beatIndex: Int,
        start: Double,
        end: Double,
        samples: [FaceTrackingSample],
        averageFace: CGRect?,
        confidence: Float,
        maxFaceCount: Int,
        detectionRate: Double,
        isScreenShare: Bool
    ) {
        self.beatIndex = beatIndex
        self.start = start
        self.end = end
        self.samples = samples
        self.averageFace = averageFace
        self.confidence = confidence
        self.maxFaceCount = maxFaceCount
        self.detectionRate = detectionRate
        self.isScreenShare = isScreenShare
    }
}

// MARK: - Servicio principal
/// Servicio de Computer Vision para detección facial y reencuadre dinámico 9:16 con suavizado Lerp
public final class FaceTrackingService {
    public static let shared = FaceTrackingService()

    /// Factor de interpolación (0.05 a 0.15 para paneo cinemático suave)
    public var lerpFactor: CGFloat = 0.08

    /// Zona muerta normalizada: movimientos menores no mueven el encuadre para evitar temblores
    public var deadzoneThreshold: CGFloat = 0.035

    /// Tope de frames por llamada para no saturar el MediaAnalysisDaemon
    public var maxSamplesPerTrack: Int = 40

    public init() {}

    // MARK: - API principal (F3: muestreo denso + trayectoria real)

    /// Analiza un rango y devuelve la trayectoria suavizada del orador.
    /// F3: muestrea cada `sampleIntervalSeconds` (adaptativo con tope), usa mediana
    /// robusta + EMA con deadzone, y por fin devuelve `samples` reales.
    public func trackSpeaker(
        in asset: AVAsset,
        timeRange: TimeRange? = nil,
        sampleIntervalSeconds: Double = 0.5
    ) async throws -> (samples: [FaceTrackingSample], averageFace: CGRect?, isScreenShare: Bool) {
        guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else {
            return ([], nil, false)
        }

        let totalDuration = try await asset.load(.duration).seconds
        let startTime = max(0, timeRange?.start ?? 0)
        let endTime = min(totalDuration, timeRange?.end ?? totalDuration)
        guard endTime > startTime else { return ([], nil, false) }

        let track = await trackRange(in: asset, start: startTime, end: endTime, requestedInterval: sampleIntervalSeconds)
        return (track.samples, track.averageFace, track.isScreenShare)
    }

    /// F3/F5: tracking por beat — cada storyBeat se muestrea por separado para que
    /// el encuadre pueda decidir por beat (hook con cara, pantalla sin cara, etc).
    public func trackBeats(
        in asset: AVAsset,
        beats: [(start: Double, end: Double)],
        sampleIntervalSeconds: Double = 0.5
    ) async throws -> [BeatFaceTrack] {
        guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else {
            return beats.enumerated().map {
                BeatFaceTrack(beatIndex: $0.offset, start: $0.element.start, end: $0.element.end, samples: [], averageFace: nil, confidence: 0, maxFaceCount: 0, detectionRate: 0, isScreenShare: false)
            }
        }
        var out: [BeatFaceTrack] = []
        for (i, beat) in beats.enumerated() {
            let track = await trackRange(in: asset, start: beat.start, end: beat.end, requestedInterval: sampleIntervalSeconds)
            out.append(
                BeatFaceTrack(
                    beatIndex: i,
                    start: beat.start,
                    end: beat.end,
                    samples: track.samples,
                    averageFace: track.averageFace,
                    confidence: track.confidence,
                    maxFaceCount: track.maxFaceCount,
                    detectionRate: track.detectionRate,
                    isScreenShare: track.isScreenShare
                )
            )
        }
        return out
    }

    // MARK: - Núcleo de tracking de un rango

    private struct RangeTrack {
        let samples: [FaceTrackingSample]
        let averageFace: CGRect?
        let confidence: Float
        let maxFaceCount: Int
        let detectionRate: Double
        let isScreenShare: Bool
    }

    private func trackRange(
        in asset: AVAsset,
        start: Double,
        end: Double,
        requestedInterval: Double
    ) async -> RangeTrack {
        let duration = max(0.1, end - start)
        // Intervalo adaptativo: nunca más de maxSamplesPerTrack frames por rango
        let interval = max(requestedInterval, duration / Double(max(1, maxSamplesPerTrack)))
        var sampleTimes: [Double] = []
        var t = start + min(0.25, duration * 0.1)
        while t <= end - 0.05 && sampleTimes.count < maxSamplesPerTrack {
            sampleTimes.append(t)
            t += interval
        }
        if sampleTimes.isEmpty { sampleTimes = [(start + end) / 2.0] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        struct RawHit { let time: Double; let rect: CGRect; let confidence: Float; let count: Int }
        var hits: [RawHit] = []
        var maxCount = 0

        for sampleTime in sampleTimes {
            let cmTime = CMTime(seconds: sampleTime, preferredTimescale: 600)
            guard let imageRef = try? await generator.image(at: cmTime).image else { continue }
            let faces = detectFaces(in: imageRef)
            maxCount = max(maxCount, faces.count)
            if let main = faces.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) {
                hits.append(RawHit(time: sampleTime, rect: main.rect, confidence: main.confidence, count: faces.count))
            } else if let human = detectHumanFallback(in: imageRef) {
                // Fallback: persona de espaldas / sin cara visible -> confianza baja
                hits.append(RawHit(time: sampleTime, rect: human.rect, confidence: 0.25, count: 1))
            }
        }

        // FIX-regresión PiP: si a 640px no se vio nada (webcam chiquita), reintentar
        // una vez en alta (960px) con un subset de frames para no saturar el MAD.
        if hits.isEmpty && duration >= 2.0 {
            generator.maximumSize = CGSize(width: 960, height: 540)
            let retryTimes = Array(sampleTimes.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).prefix(12))
            for sampleTime in retryTimes {
                let cmTime = CMTime(seconds: sampleTime, preferredTimescale: 600)
                guard let imageRef = try? await generator.image(at: cmTime).image else { continue }
                let faces = detectFaces(in: imageRef)
                maxCount = max(maxCount, faces.count)
                if let main = faces.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) {
                    hits.append(RawHit(time: sampleTime, rect: main.rect, confidence: main.confidence, count: faces.count))
                }
            }
            if !hits.isEmpty {
                print("🔍 [Vision] Reintento en alta rescató \(hits.count) detecciones")
            }
        }

        guard !hits.isEmpty else {
            return RangeTrack(samples: [], averageFace: nil, confidence: 0, maxFaceCount: maxCount, detectionRate: 0, isScreenShare: false)
        }

        // FIX-regresión "recorte a medias": rechazo de outliers por ancla.
        // Si hay una cara en pantalla (thumbnail, videollamada) además de la tuya,
        // la mediana global caía en el medio y te cortaba a la mitad. El ancla es
        // la detección con más área×confianza; se descartan hits lejanos a ella.
        let filtered = Self.rejectOutliers(hits, rect: { $0.rect }, confidence: { $0.confidence })
        let rects = filtered.map(\.rect)
        guard let median = Self.medianRect(of: rects) else {
            return RangeTrack(samples: [], averageFace: nil, confidence: 0, maxFaceCount: maxCount, detectionRate: 0, isScreenShare: false)
        }

        let centers = Self.smoothCenters(
            filtered.map { ($0.time, $0.rect) },
            lerpFactor: lerpFactor,
            deadzone: deadzoneThreshold
        )
        let samples = zip(filtered, centers).map { hit, sm in
            FaceTrackingSample(timestamp: hit.time, boundingBox: hit.rect, smoothedCenterX: sm.x, smoothedCenterY: sm.y)
        }
        let meanConf = filtered.map(\.confidence).reduce(0, +) / Float(filtered.count)
        let detectionRate = Double(filtered.count) / Double(sampleTimes.count)
        let isScreenShare = Self.isScreenShare(face: median)

        if isScreenShare {
            print("💻 [Vision] Webcam PiP detectada en: (\(median.midX), \(median.midY)) w=\(median.width) h=\(median.height) conf=\(meanConf) n=\(filtered.count)/\(sampleTimes.count)")
        } else {
            print("👤 [Vision] Hablante detectado en: (\(median.midX), \(median.midY)) w=\(median.width) h=\(median.height) conf=\(meanConf) n=\(filtered.count)/\(sampleTimes.count)")
        }

        return RangeTrack(
            samples: samples,
            averageFace: median,
            confidence: meanConf,
            maxFaceCount: maxCount,
            detectionRate: detectionRate,
            isScreenShare: isScreenShare
        )
    }

    // MARK: - Detección

    /// Todos los rostros del frame con confianza (origen arriba-izquierda normalizado).
    public func detectFaces(in cgImage: CGImage) -> [FaceDetection] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let results = request.results, !results.isEmpty else { return [] }
        return results.map {
            FaceDetection(
                rect: CGRect(
                    x: $0.boundingBox.origin.x,
                    y: 1.0 - $0.boundingBox.origin.y - $0.boundingBox.height,
                    width: $0.boundingBox.width,
                    height: $0.boundingBox.height
                ),
                confidence: $0.confidence
            )
        }
    }

    /// Detecta el rostro principal (más grande) en una imagen CGImage
    public func detectMainFace(in cgImage: CGImage) -> CGRect? {
        let faces = detectFaces(in: cgImage)
        return faces.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) })?.rect
    }

    /// Fallback cuando no hay cara (de espaldas, mascarilla): rect superior del cuerpo.
    public func detectHumanFallback(in cgImage: CGImage) -> FaceDetection? {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let results = request.results, !results.isEmpty else { return nil }
        guard let best = results.max(by: { ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height) }) else { return nil }
        // La cabeza ocupa aproximadamente el tercio superior del cuerpo
        let b = best.boundingBox
        let headH = b.height * 0.32
        let head = CGRect(x: b.origin.x, y: b.origin.y + b.height - headH, width: b.width, height: headH)
        return FaceDetection(
            rect: CGRect(x: head.origin.x, y: 1.0 - head.origin.y - head.height, width: head.width, height: head.height),
            confidence: 0.25
        )
    }

    // MARK: - Helpers puros (testeables sin video)

    /// Mediana por componente — robusta a outliers (parpadeos, falsos positivos).
    public static func medianRect(of rects: [CGRect]) -> CGRect? {
        guard !rects.isEmpty else { return nil }
        func median(_ values: [CGFloat]) -> CGFloat {
            let s = values.sorted()
            if s.count % 2 == 1 { return s[s.count / 2] }
            return (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
        }
        // Mediana sobre centros + tamaños (más estable que sobre origins)
        let midsX = rects.map(\.midX)
        let midsY = rects.map(\.midY)
        let widths = rects.map(\.width)
        let heights = rects.map(\.height)
        let mx = median(midsX), my = median(midsY), w = median(widths), h = median(heights)
        return CGRect(x: mx - w / 2.0, y: my - h / 2.0, width: w, height: h)
    }

    /// Suavizado EMA con zona muerta. Devuelve centros suavizados por muestra.
    public static func smoothCenters(
        _ hits: [(time: Double, rect: CGRect)],
        lerpFactor: CGFloat,
        deadzone: CGFloat
    ) -> [(x: CGFloat, y: CGFloat)] {
        guard !hits.isEmpty else { return [] }
        var out: [(x: CGFloat, y: CGFloat)] = []
        var smX = hits[0].rect.midX
        var smY = hits[0].rect.midY
        out.append((smX, smY))
        for hit in hits.dropFirst() {
            let rawX = hit.rect.midX, rawY = hit.rect.midY
            let candX = smX + (rawX - smX) * lerpFactor
            let candY = smY + (rawY - smY) * lerpFactor
            // Zona muerta: ignora micro-movimientos para evitar temblor
            if abs(candX - smX) >= deadzone { smX = candX }
            if abs(candY - smY) >= deadzone { smY = candY }
            out.append((smX, smY))
        }
        return out
    }

    /// Rechazo de outliers por ancla (testeable): el ancla es el hit con más
    /// área×confianza; se conservan los hits a <0.22 de distancia normalizada.
    /// Si todo queda fuera, se conserva solo el ancla (nunca vacío si hay hits).
    public static func rejectOutliers<T>(
        _ hits: [T],
        rect: (T) -> CGRect,
        confidence: (T) -> Float,
        maxDistance: CGFloat = 0.22
    ) -> [T] {
        guard !hits.isEmpty else { return [] }
        guard hits.count > 1 else { return hits }
        let anchor = hits.max(by: {
            let a = rect($0), b = rect($1)
            return (a.width * a.height) * CGFloat(confidence($0)) < (b.width * b.height) * CGFloat(confidence($1))
        })!
        let ax = rect(anchor).midX, ay = rect(anchor).midY
        let kept = hits.filter {
            let r = rect($0)
            let dx = r.midX - ax, dy = r.midY - ay
            return (dx * dx + dy * dy).squareRoot() <= maxDistance
        }
        return kept.isEmpty ? [anchor] : kept
    }

    /// Si el rostro ocupa menos del 25% del frame, es ventanita de webcam (PiP).
    public static func isScreenShare(face: CGRect) -> Bool {
        face.width < 0.25 && face.height < 0.28
    }

    // MARK: - Crop (se mantiene por compat; F4 lo centraliza en FaceCropCalculator)

    /// Calcula la matriz de transformación para un frame de video 16:9 a 9:16 (1080x1920)
    public func calculateCropTransform(
        originalSize: CGSize,
        targetSize: CGSize = CGSize(width: 1080, height: 1920),
        centerX: CGFloat,
        centerY: CGFloat,
        mode: FramingMode
    ) -> CGAffineTransform {
        switch mode {
        case .autoFaceTrack:
            // Escalar de modo que la altura del video llene la altura 1920 (aspect fill)
            let scale = targetSize.height / originalSize.height
            let scaledWidth = originalSize.width * scale

            // Centrar la ventana de 1080px alrededor del rostro del orador
            let focusX = scaledWidth * centerX
            var offsetX = (targetSize.width / 2.0) - focusX

            // Evitar barras negras a los lados
            let maxOffsetX: CGFloat = 0
            let minOffsetX: CGFloat = targetSize.width - scaledWidth
            offsetX = min(max(offsetX, minOffsetX), maxOffsetX)

            var transform = CGAffineTransform.identity
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: offsetX / scale, y: 0)
            return transform

        case .manualCrop:
            let scale = targetSize.height / originalSize.height
            let scaledWidth = originalSize.width * scale
            let offsetX = (targetSize.width - scaledWidth) / 2.0

            var transform = CGAffineTransform.identity
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: offsetX / scale, y: 0)
            return transform

        case .splitScreen:
            // Mitad superior enfocando el rostro ampliado
            let scale = (targetSize.height * 0.5) / (originalSize.height * 0.5)
            var transform = CGAffineTransform.identity
            transform = transform.scaledBy(x: scale, y: scale)
            return transform

        case .blurredBackground:
            // Ajustar el video al centro sin recortar la pantalla (ancho 1080)
            let scale = targetSize.width / originalSize.width
            let scaledHeight = originalSize.height * scale
            let offsetY = (targetSize.height - scaledHeight) / 2.0

            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: 0, y: offsetY)
            transform = transform.scaledBy(x: scale, y: scale)
            return transform
        }
    }
}
