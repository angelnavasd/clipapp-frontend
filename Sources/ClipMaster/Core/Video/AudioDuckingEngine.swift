import Foundation
import AVFoundation

public struct DuckingSpeechInterval {
    public let start: CMTime
    public let end: CMTime

    public init(start: CMTime, end: CMTime) {
        self.start = start
        self.end = end
    }
}

/// Motor de Auto-Ducking para música de fondo sincronizado con la voz del orador
public final class AudioDuckingEngine {
    public static let shared = AudioDuckingEngine()

    public init() {}

    /// Crea la configuración de AVAudioMix para atenuar la música durante el habla
    /// - Parameters:
    ///   - musicTrack: Pista de audio de la composición donde está la música
    ///   - speechIntervals: Rangos temporales donde hay voz activa
    ///   - totalDuration: Duración total del clip renderizado
    ///   - speechMusicVolume: Volumen durante el habla (~ -18 dB -> 0.125)
    ///   - silenceMusicVolume: Volumen en silencios (~ -10 dB -> 0.316)
    ///   - rampDurationSeconds: Duración de la rampa de transición suave (0.15s)
    public func createDuckingAudioMix(
        musicTrack: AVCompositionTrack,
        speechIntervals: [DuckingSpeechInterval],
        totalDuration: CMTime,
        speechMusicVolume: Float = 0.125,
        silenceMusicVolume: Float = 0.316,
        rampDurationSeconds: Double = 0.15
    ) -> AVAudioMix {
        let mixParameters = AVMutableAudioMixInputParameters(track: musicTrack)
        let rampDuration = CMTime(seconds: rampDurationSeconds, preferredTimescale: 600)

        // Estado inicial
        var currentTime = CMTime.zero

        if speechIntervals.isEmpty {
            mixParameters.setVolume(silenceMusicVolume, at: .zero)
        } else {
            for interval in speechIntervals {
                // Si hay un espacio de silencio antes de este bloque de habla, subir música
                if interval.start > currentTime {
                    let silenceRange = CMTimeRange(start: currentTime, end: interval.start)
                    mixParameters.setVolumeRamp(
                        fromStartVolume: speechMusicVolume,
                        toEndVolume: silenceMusicVolume,
                        timeRange: CMTimeRange(start: currentTime, duration: min(rampDuration, silenceRange.duration))
                    )
                }

                // Inicia el habla: bajar la música suavemente (Auto-Ducking)
                let duckRange = CMTimeRange(start: interval.start, duration: min(rampDuration, CMTimeSubtract(interval.end, interval.start)))
                mixParameters.setVolumeRamp(
                    fromStartVolume: silenceMusicVolume,
                    toEndVolume: speechMusicVolume,
                    timeRange: duckRange
                )

                currentTime = interval.end
            }

            // Silencio final tras el último segmento de habla
            if currentTime < totalDuration {
                let tailDuration = CMTimeSubtract(totalDuration, currentTime)
                mixParameters.setVolumeRamp(
                    fromStartVolume: speechMusicVolume,
                    toEndVolume: silenceMusicVolume,
                    timeRange: CMTimeRange(start: currentTime, duration: min(rampDuration, tailDuration))
                )
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [mixParameters]
        return audioMix
    }
}
