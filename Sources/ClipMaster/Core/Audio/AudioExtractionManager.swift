import Foundation
import AVFoundation

public enum AudioExtractionError: Error, LocalizedError {
    case noAudioTrackFound
    case readerInitializationFailed
    case bufferAllocationFailed
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrackFound:
            return "No se encontró pista de audio en el archivo de video."
        case .readerInitializationFailed:
            return "No se pudo inicializar AVAssetReader para el audio."
        case .bufferAllocationFailed:
            return "Fallo en la asignación del buffer de audio PCM."
        case .exportFailed(let reason):
            return "Error al extraer audio: \(reason)"
        }
    }
}

/// Gestor de extracción de audio local optimizado para inferencia en WhisperKit / CoreML
public final class AudioExtractionManager {
    public static let shared = AudioExtractionManager()

    public init() {}

    /// Extrae el audio de un AVAsset a un buffer Float32 a 16,000 Hz (mono), estándar para WhisperKit
    public func extractPCMFloatArray(
        from asset: AVAsset,
        timeRange: TimeRange? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws -> [Float] {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioExtractionError.noAudioTrackFound
        }

        let totalDuration = try await asset.load(.duration).seconds
        let effectiveStart = max(0, timeRange?.start ?? 0)
        let effectiveEnd = min(totalDuration, timeRange?.end ?? totalDuration)
        let duration = max(0, effectiveEnd - effectiveStart)

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioExtractionError.readerInitializationFailed
        }

        if timeRange != nil {
            let startCM = CMTime(seconds: effectiveStart, preferredTimescale: 600)
            let durCM = CMTime(seconds: duration, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: startCM, duration: durCM)
        }

        // Configuración de salida: 16 kHz Mono Float32
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw AudioExtractionError.readerInitializationFailed
        }

        reader.add(readerOutput)

        guard reader.startReading() else {
            throw AudioExtractionError.exportFailed(reader.error?.localizedDescription ?? "Desconocido")
        }

        var floatSamples: [Float] = []
        // Reservar capacidad estimada (~16,000 muestras por segundo)
        if duration > 0 {
            floatSamples.reserveCapacity(Int(duration * 16000))
        }

        var lastReportedTime: Double = 0

        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                break
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)

            data.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }

            let sampleCount = length / MemoryLayout<Float>.size
            data.withUnsafeBytes { rawBuffer in
                guard let pointer = rawBuffer.bindMemory(to: Float.self).baseAddress else { return }
                floatSamples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: sampleCount))
            }

            if let progress = progress, duration > 0 {
                let currentSec = Double(floatSamples.count) / 16000.0
                if currentSec - lastReportedTime > 1.0 {
                    lastReportedTime = currentSec
                    progress(min(1.0, currentSec / duration))
                }
            }
        }

        if reader.status == .failed {
            throw AudioExtractionError.exportFailed(reader.error?.localizedDescription ?? "Error al leer samples")
        }

        progress?(1.0)
        return floatSamples
    }
}
