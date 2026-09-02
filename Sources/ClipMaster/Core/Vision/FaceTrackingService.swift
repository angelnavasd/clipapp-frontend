import Foundation
import Vision
import CoreGraphics
import AVFoundation

public struct FaceTrackingSample: Equatable {
    public let timestamp: Double
    public let boundingBox: CGRect // Coordenadas normalizadas [0, 1] de Vision
    public let smoothedCenterX: CGFloat
    public let smoothedCenterY: CGFloat
}

/// Servicio de Computer Vision para detección facial y reencuadre dinámico 9:16 con suavizado Lerp
public final class FaceTrackingService {
    public static let shared = FaceTrackingService()

    /// Factor de interpolación (0.05 a 0.15 para paneo cinemático suave)
    public var lerpFactor: CGFloat = 0.08

    /// Zona muerta normalizada: movimientos menores no mueven el encuadre para evitar temblores
    public var deadzoneThreshold: CGFloat = 0.035

    public init() {}

    /// Analiza una secuencia de cuadros de video y calcula la trayectoria del orador suavizada
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

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var samples: [FaceTrackingSample] = []
        var detectedFaces: [CGRect] = []
        var currentTime: Double = startTime
        var currentSmoothedX: CGFloat = 0.5
        var currentSmoothedY: CGFloat = 0.5

        while currentTime < endTime {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            if let imageRef = try? await generator.image(at: cmTime).image {
                let faceRect = detectMainFace(in: imageRef)

                if let face = faceRect {
                    detectedFaces.append(face)
                    let targetCenterX = face.midX
                    let targetCenterY = face.midY

                    // Aplicar Deadzone
                    let deltaX = abs(targetCenterX - currentSmoothedX)
                    if deltaX > deadzoneThreshold {
                        currentSmoothedX += (targetCenterX - currentSmoothedX) * lerpFactor
                    }

                    let deltaY = abs(targetCenterY - currentSmoothedY)
                    if deltaY > deadzoneThreshold {
                        currentSmoothedY += (targetCenterY - currentSmoothedY) * lerpFactor
                    }

                    samples.append(
                        FaceTrackingSample(
                            timestamp: currentTime,
                            boundingBox: face,
                            smoothedCenterX: currentSmoothedX,
                            smoothedCenterY: currentSmoothedY
                        )
                    )
                }
            }

            currentTime += sampleIntervalSeconds
        }

        var avgFace: CGRect? = nil
        var isScreenShare = false

        if !detectedFaces.isEmpty {
            let avgX = detectedFaces.map(\.origin.x).reduce(0, +) / CGFloat(detectedFaces.count)
            let avgY = detectedFaces.map(\.origin.y).reduce(0, +) / CGFloat(detectedFaces.count)
            let avgW = detectedFaces.map(\.width).reduce(0, +) / CGFloat(detectedFaces.count)
            let avgH = detectedFaces.map(\.height).reduce(0, +) / CGFloat(detectedFaces.count)
            avgFace = CGRect(x: avgX, y: avgY, width: avgW, height: avgH)

            // Detección de Screen Share con Webcam:
            // Si el rostro ocupa menos del 20% del ancho/alto y está ubicado en una esquina o borde
            if avgW < 0.22 && avgH < 0.25 {
                isScreenShare = true
                print("💻 Screen Share con Webcam detectado! El rostro ocupa solo \(Int(avgW * 100))% de la pantalla.")
            }
        }

        return (samples, avgFace, isScreenShare)
    }

    /// Detecta el rostro principal (más grande) en una imagen CGImage
    public func detectMainFace(in cgImage: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        try? handler.perform([request])

        guard let results = request.results, !results.isEmpty else {
            return nil
        }

        // Seleccionar el rostro con mayor área relativa (orador principal)
        let mainFace = results.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
        })

        guard let face = mainFace else { return nil }

        // Vision usa coordenadas con origen abajo-izquierda, convertimos a origen arriba-izquierda
        return CGRect(
            x: face.boundingBox.origin.x,
            y: 1.0 - face.boundingBox.origin.y - face.boundingBox.height,
            width: face.boundingBox.width,
            height: face.boundingBox.height
        )
    }

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
