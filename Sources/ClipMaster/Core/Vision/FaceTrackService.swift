import AVFoundation
import CoreGraphics
import ImageIO
import Vision

/// Tracking facial continuo estilo Opus ($0, on-device, sin red).
/// Muestrea el clip denso en el tiempo, asocia la cara dominante entre
/// muestras y entrega una curva suavizada: la ventana 9:16 la *sigue*.
/// Sin saltos por beat, sin tracking agresivo (sin zoom, full-height).
public enum FaceTrackService {

    /// Una muestra de la curva: centro normalizado 0-1 (origen arriba-izq)
    /// + ancho de cara (fracción del ancho) + confianza.
    public struct Sample: Equatable, Sendable {
        public let t: Double
        public let x: Double
        public let y: Double
        public let w: Double
        public let conf: Double
    }

    /// Curva completa de un clip + instantes de corte duro (cambio de cara).
    public struct Track: Equatable, Sendable {
        public let samples: [Sample]
        public let hardCuts: [Double]
    }

    /// Paso ideal entre muestras (s). Se adapta para no pasar `maxSamples`.
    public static var step: Double = 0.25
    public static var maxSamples: Int = 64
    /// Suavizado exponencial (0-1, menor = más lento) y deadzone.
    public static var alpha: Double = 0.3
    public static var deadzone: Double = 0.03
    /// Salto de centro que se considera otra persona/toma -> corte duro.
    public static var jumpCutThreshold: Double = 0.28

    /// Trackea `range` del asset. Nunca falla: sin caras devuelve curva
    /// neutra (0.5, 0.45) para no romper preview ni export.
    public static func track(in asset: AVAsset, range: (start: Double, end: Double)) async -> Track {
        let dur = range.end - range.start
        guard dur > 0.05 else { return neutral(range: range) }
        let step = max(Self.step, dur / Double(maxSamples))
        var times: [Double] = []
        var t = range.start + min(0.15, dur / 2)
        while t < range.end {
            times.append(t)
            t += step
        }
        guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else { return neutral(range: range) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var raws: [(t: Double, rect: CGRect?, conf: Double)] = []
        for t in times {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            guard let imageRef = try? await generator.image(at: cmTime).image else { continue }
            let faces = detect(in: imageRef)
            let currRect: CGRect?
            let currConf: Double
            if let main = faces.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) {
                currRect = main.rect
                currConf = Double(main.confidence)
            } else if let human = FaceTrackingService.shared.detectHumanFallback(in: imageRef) {
                currRect = human.rect
                currConf = 0.25
            } else {
                currRect = nil
                currConf = 0
            }

            // Si detectamos un salto brusco de encuadre respecto a la muestra previa,
            // refinamos el corte con una muestra intermedia para sincronización a nivel de frame.
            if let prev = raws.last, let pr = prev.rect, let cr = currRect {
                let dx = Double(cr.midX - pr.midX)
                let dy = Double(cr.midY - pr.midY)
                let isPosJump = hypot(dx, dy) > jumpCutThreshold
                let pw = Double(pr.width), cw = Double(cr.width)
                let isSzJump = abs(cw - pw) > 0.10 || (cw / max(0.01, pw) > 1.7) || (pw / max(0.01, cw) > 1.7)
                if isPosJump || isSzJump {
                    let midT = (prev.t + t) / 2.0
                    let midCM = CMTime(seconds: midT, preferredTimescale: 600)
                    if let midImg = try? await generator.image(at: midCM).image {
                        let midFaces = detect(in: midImg)
                        if let midMain = midFaces.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) {
                            raws.append((midT, midMain.rect, Double(midMain.confidence)))
                        }
                    }
                }
            }

            raws.append((t, currRect, currConf))
        }
        return smooth(raws: raws, range: range)
    }

    // MARK: - Núcleo puro (testeable sin video)

    /// Asocia + suaviza muestras crudas. Puro: entra geometría, sale curva.
    static func smooth(raws: [(t: Double, rect: CGRect?, conf: Double)], range: (start: Double, end: Double)) -> Track {
        var samples: [Sample] = []
        var hardCuts: [Double] = []
        var sx: Double? = nil
        var sy: Double? = nil
        var sw: Double? = nil
        for r in raws {
            guard let rect = r.rect else {
                // Sin cara: mantener última posición (gap), confianza 0.
                if let x = sx, let y = sy {
                    samples.append(Sample(t: r.t, x: x, y: y, w: sw ?? 0.25, conf: 0))
                } else {
                    samples.append(Sample(t: r.t, x: 0.5, y: 0.45, w: 0.25, conf: 0))
                }
                continue
            }
            // detectFaces already converted Vision coordinates to top-left origin.
            let cx = Double(rect.midX), cy = Double(rect.midY), w = Double(rect.width)
            let isPositionJump = (sx != nil && sy != nil) && hypot(cx - sx!, cy - sy!) > jumpCutThreshold
            let isSizeJump = (sw != nil) && (abs(w - sw!) > 0.10 || (w / max(0.01, sw!) > 1.7) || (sw! / max(0.01, w) > 1.7))

            if isPositionJump || isSizeJump {
                // Otra persona u otra toma (ej. salto de webcam a talking head): corte duro, reanclar sin rampa.
                hardCuts.append(r.t)
                sx = cx; sy = cy; sw = w
                samples.append(Sample(t: r.t, x: cx, y: cy, w: w, conf: r.conf))
                continue
            }
            if sx == nil {
                sx = cx; sy = cy; sw = w
            } else {
                // Media móvil con deadzone: ignora micro-movimientos.
                let nx = sx! + alpha * (cx - sx!)
                let ny = sy! + alpha * (cy - sy!)
                if abs(nx - sx!) > deadzone { sx = nx }
                if abs(ny - sy!) > deadzone { sy = ny }
                sw = (sw ?? w) + alpha * (w - (sw ?? w))
            }
            samples.append(Sample(t: r.t, x: sx!, y: sy!, w: sw ?? w, conf: r.conf))
        }
        if samples.isEmpty { return neutral(range: range) }
        return Track(samples: samples, hardCuts: hardCuts)
    }

    /// Centro de la curva en `t` (interpola entre muestras vecinas o salta si hay hardCut).
    public static func center(at t: Double, in track: Track) -> (x: Double, y: Double, w: Double) {
        guard !track.samples.isEmpty else { return (0.5, 0.45, 0.25) }
        if t <= track.samples[0].t { let s = track.samples[0]; return (s.x, s.y, s.w) }
        if t >= track.samples.last!.t { let s = track.samples.last!; return (s.x, s.y, s.w) }
        for i in 1 ..< track.samples.count {
            let a = track.samples[i - 1], b = track.samples[i]
            if t <= b.t {
                // Si entre a y b hay un corte duro de escena, hacer el salto limpio en el corte
                if let cut = track.hardCuts.first(where: { $0 > a.t && $0 <= b.t }) {
                    return t < cut ? (a.x, a.y, a.w) : (b.x, b.y, b.w)
                }
                let f = (t - a.t) / max(1e-6, b.t - a.t)
                return (a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.w + (b.w - a.w) * f)
            }
        }
        let s = track.samples.last!
        return (s.x, s.y, s.w)
    }

    // MARK: - Privado

    private static func neutral(range: (start: Double, end: Double)) -> Track {
        let mid = (range.start + range.end) / 2
        return Track(samples: [Sample(t: mid, x: 0.5, y: 0.45, w: 0.25, conf: 0)], hardCuts: [])
    }

    private static func detect(in cg: CGImage) -> [FaceDetection] {
        FaceTrackingService.shared.detectFaces(in: cg)
    }

    private static func cgImage(from jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
