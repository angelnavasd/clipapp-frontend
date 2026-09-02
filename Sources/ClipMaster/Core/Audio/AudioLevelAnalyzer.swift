import Foundation
import Accelerate

public struct AudioTimeWindow: Equatable {
    public let startTime: Double
    public let endTime: Double
    public let rms: Float
    public let decibels: Float
    public let isSilence: Bool

    public init(
        startTime: Double,
        endTime: Double,
        rms: Float,
        decibels: Float,
        isSilence: Bool
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.rms = rms
        self.decibels = decibels
        self.isSilence = isSilence
    }
}

/// Analizador de señal de audio acelerado por hardware con Accelerate (vDSP)
public final class AudioLevelAnalyzer {
    public static let shared = AudioLevelAnalyzer()

    /// Umbral en dB por debajo del cual se considera silencio/pausa muerta
    public var silenceThresholdDb: Float = -26.0

    public init(silenceThresholdDb: Float = -26.0) {
        self.silenceThresholdDb = silenceThresholdDb
    }

    /// Analiza una pista PCM de Float32 en ventanas temporales (por defecto 100ms)
    /// - Parameters:
    ///   - samples: Muestras de audio normalizadas [-1.0, 1.0]
    ///   - sampleRate: Frecuencia de muestreo (típicamente 16000 Hz)
    ///   - windowDurationMs: Duración de cada ventana en milisegundos (100ms)
    /// - Returns: Arreglo de ventanas temporales con nivel RMS y dB
    public func analyzeEnergyProfile(
        samples: [Float],
        sampleRate: Double = 16000.0,
        windowDurationMs: Double = 100.0
    ) -> [AudioTimeWindow] {
        guard !samples.isEmpty else { return [] }

        let windowSize = Int((windowDurationMs / 1000.0) * sampleRate)
        guard windowSize > 0 else { return [] }

        let totalWindows = samples.count / windowSize
        var results: [AudioTimeWindow] = []
        results.reserveCapacity(totalWindows)

        let stepTime = Double(windowSize) / sampleRate

        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            for i in 0..<totalWindows {
                let offset = i * windowSize
                let windowPointer = baseAddress.advanced(by: offset)

                // Cálculo RMS acelerado vectorialmente con vDSP
                var meanSquare: Float = 0.0
                vDSP_measqv(windowPointer, 1, &meanSquare, vDSP_Length(windowSize))
                let rms = sqrt(max(meanSquare, 1e-9))

                // dBFS = 20 * log10(rms)
                let db = 20.0 * log10(max(rms, 1e-5))

                let startTime = Double(i) * stepTime
                let endTime = startTime + stepTime
                let isSilence = db < silenceThresholdDb

                results.append(
                    AudioTimeWindow(
                        startTime: startTime,
                        endTime: endTime,
                        rms: rms,
                        decibels: db,
                        isSilence: isSilence
                    )
                )
            }
        }

        return results
    }

    /// Obtiene el decibel promedio para un rango temporal específico [start, end]
    public func averageDb(
        in windows: [AudioTimeWindow],
        start: Double,
        end: Double
    ) -> Double {
        let matching = windows.filter { $0.startTime >= start && $0.endTime <= end }
        guard !matching.isEmpty else { return -20.0 }
        let sum = matching.reduce(0.0) { $0 + Double($1.decibels) }
        return (sum / Double(matching.count)).rounded(toPlaces: 1)
    }

    /// Detecta rangos de silencio consecutivos de duración mayor a minDurationSeconds
    public func detectSilenceGaps(
        in windows: [AudioTimeWindow],
        minDurationSeconds: Double = 0.5
    ) -> [(start: Double, end: Double)] {
        var gaps: [(start: Double, end: Double)] = []
        var currentGapStart: Double? = nil

        for window in windows {
            if window.isSilence {
                if currentGapStart == nil {
                    currentGapStart = window.startTime
                }
            } else {
                if let start = currentGapStart {
                    let duration = window.startTime - start
                    if duration >= minDurationSeconds {
                        gaps.append((start: start, end: window.startTime))
                    }
                    currentGapStart = nil
                }
            }
        }

        if let start = currentGapStart, let lastWindow = windows.last {
            if (lastWindow.endTime - start) >= minDurationSeconds {
                gaps.append((start: start, end: lastWindow.endTime))
            }
        }

        return gaps
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
