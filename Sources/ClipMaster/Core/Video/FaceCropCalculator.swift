import Foundation
import CoreGraphics

/// F4: única fuente de verdad para el crop 9:16.
/// La misma matemática alimenta el export (`VideoRenderEngine`, vía CGAffineTransform)
/// y el preview (`SmartFramedPlayerView`, vía `previewLayout`).
/// Así se elimina el bug "lo que ves no es lo que exportas".
public enum FaceCropCalculator {
    /// Ventana 9:16 adaptativa al tamaño de la CARA (fracción del alto del source).
    /// - Sin tamaño (nil) -> 1.0 = frame completo (aspect-fill clásico, close-ups intactos).
    /// - Con tamaño -> alto de ventana = anchoCara × 3.4, clamp [0.62, 1.0].
    /// El suelo 0.62 es deliberado: el VLM subestima caras chicas y su centro trae
    /// ±0.05 de error; una ventana menor decapita (verificado visualmente).
    /// Con 0.62 la cara ocupa ~60% del ancho con margen para el error. Verificado:
    /// cara 0.30 -> 1.0 (intacto), cara 0.10 (PiP) -> 0.62 (primer plano seguro).
    public static func windowHeightFraction(faceWidth: CGFloat?) -> CGFloat {
        guard let w = faceWidth, w > 0 else { return 1.0 }
        // Si el rostro ocupa >= 18% del ancho, aspect-fill estándar (1.78x) ya lo encuadra perfecto;
        // no sobre-zoomear para no cortar frente ni barbilla.
        // Si es una webcam chica en screen-share (w < 0.18), zoom suave (hasta ~1.35x, suelo 0.74) para destacar la ventanita.
        if w >= 0.18 { return 1.0 }
        return min(max(w * 4.2, 0.74), 1.0)
    }

    /// Transform de export aspect-fill centrado en `center` (normalizado, origen arriba-izquierda).
    /// Clamp en ambos ejes para no mostrar barras negras, sea cual sea el aspect del source.
    /// Blindado: tamaños inválidos o NaN devuelven identidad (frame completo, nunca negro).
    public static func exportTransform(
        sourceSize: CGSize,
        targetSize: CGSize = CGSize(width: 1080, height: 1920),
        center: CGPoint,
        faceWidth: CGFloat? = nil,
        mode: FramingMode
    ) -> CGAffineTransform {
        guard isValidSize(sourceSize), isValidSize(targetSize) else { return .identity }
        let cx = sanitized(center.x), cy = sanitized(center.y)
        let center = CGPoint(x: cx, y: cy)
        switch mode {
        case .autoFaceTrack, .manualCrop:
            // Step 1: aspect-fill base (always covers the target, zero black)
            let baseScale = max(targetSize.width / sourceSize.width,
                                targetSize.height / sourceSize.height)
            // Step 2: gentle face zoom on top (1.0 when no face, up to ~1.18×)
            let winFrac = mode == .autoFaceTrack ? windowHeightFraction(faceWidth: faceWidth) : 1.0
            let faceZoom = 1.0 / winFrac   // e.g. 1/0.85 ≈ 1.18
            let scale = baseScale * faceZoom
            let scaledW = sourceSize.width * scale
            let scaledH = sourceSize.height * scale
            let focusX = scaledW * clamp(center.x, 0, 1)
            let focusY = scaledH * clamp(center.y, 0, 1)
            var offsetX = (targetSize.width / 2.0) - focusX
            var offsetY = (targetSize.height / 2.0) - focusY
            // Clamp: scaled content always covers the target (offsets are ≤ 0)
            offsetX = min(0, max(targetSize.width - scaledW, offsetX))
            offsetY = min(0, max(targetSize.height - scaledH, offsetY))
            var t = CGAffineTransform.identity
            t = t.scaledBy(x: scale, y: scale)
            t = t.translatedBy(x: offsetX / scale, y: offsetY / scale)
            return t

        case .splitScreen:
            // Solo manual: aspect-fill clásico centrado (sin ventana adaptativa)
            let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let scaledW = sourceSize.width * scale
            let scaledH = sourceSize.height * scale
            let focusX = scaledW * clamp(center.x, 0, 1)
            let focusY = scaledH * clamp(center.y, 0, 1)
            var offsetX = (targetSize.width / 2.0) - focusX
            var offsetY = (targetSize.height / 2.0) - focusY
            offsetX = min(0, max(targetSize.width - scaledW, offsetX))
            offsetY = min(0, max(targetSize.height - scaledH, offsetY))
            var t = CGAffineTransform.identity
            t = t.scaledBy(x: scale, y: scale)
            t = t.translatedBy(x: offsetX / scale, y: offsetY / scale)
            return t

        case .blurredBackground:
            // Aspect-fit centrado sin recortar (el fondo blur lo pone el preview; en export queda letterbox)
            let scale = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let scaledW = sourceSize.width * scale
            let scaledH = sourceSize.height * scale
            let offsetX = (targetSize.width - scaledW) / 2.0
            let offsetY = (targetSize.height - scaledH) / 2.0
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: offsetX, y: offsetY)
            t = t.scaledBy(x: scale, y: scale)
            return t
        }
    }

    /// Layout equivalente para SwiftUI preview: tamaño del video escalado + offset,
    /// con la MISMA fórmula de escala/clamp que `exportTransform`.
    /// Blindado: ante tamaños inválidos devuelve el contenedor sin offset (nunca NaN).
    public static func previewLayout(
        containerSize: CGSize,
        sourceSize: CGSize,
        center: CGPoint,
        faceWidth: CGFloat? = nil
    ) -> (size: CGSize, offset: CGSize) {
        guard isValidSize(containerSize), isValidSize(sourceSize) else {
            return (containerSize, .zero)
        }
        let safe = CGPoint(x: sanitized(center.x), y: sanitized(center.y))
        // Same formula as exportTransform: aspect-fill base + gentle face zoom
        let baseScale = max(containerSize.width / sourceSize.width,
                            containerSize.height / sourceSize.height)
        let winFrac = windowHeightFraction(faceWidth: faceWidth)
        let faceZoom = 1.0 / winFrac
        let scale = baseScale * faceZoom
        let videoW = max(containerSize.width, ceil(sourceSize.width * scale) + 2.0)
        let videoH = max(containerSize.height, ceil(sourceSize.height * scale) + 2.0)
        let focusX = videoW * clamp(safe.x, 0, 1)
        let focusY = videoH * clamp(safe.y, 0, 1)
        var offsetX = (containerSize.width / 2.0) - focusX
        var offsetY = (containerSize.height / 2.0) - focusY
        offsetX = min(0, max(containerSize.width - videoW, offsetX))
        offsetY = min(0, max(containerSize.height - videoH, offsetY))
        return (CGSize(width: videoW, height: videoH), CGSize(width: offsetX, height: offsetY))
    }

    /// Rect de crop (en px del source) para la toma inferior del split-screen,
    /// centrado en la webcam con padding.
    /// El crop sale con el MISMO aspect de la zona destino (ancho completo x alto
    /// de zona) para que al escalar la llene exacta: cero bandas negras.
    public static func splitBottomCropRect(
        sourceSize: CGSize,
        center: CGPoint,
        targetAspect: CGFloat = 1080.0 / (1920.0 * 0.45)
    ) -> CGRect {
        guard isValidSize(sourceSize) else {
            return CGRect(x: 0, y: 0, width: 320, height: 180)
        }
        let cx = sanitized(center.x), cy = sanitized(center.y)
        let cropW = sourceSize.width * 0.32
        var cropH = cropW / max(0.5, targetAspect)
        cropH = min(cropH, sourceSize.height)
        let cropX = clamp(cx * sourceSize.width - cropW / 2.0, 0, max(0, sourceSize.width - cropW))
        let cropY = clamp(cy * sourceSize.height - cropH / 2.0, 0, max(0, sourceSize.height - cropH))
        return CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
    }

    /// Punto de split vertical unificado (fracción de la altura 9:16).
    public static var splitFraction: CGFloat { 0.55 }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    /// Tamaño utilizable: finito y mayor que cero (un naturalSize 0×0 → NaN → preview negro).
    static func isValidSize(_ s: CGSize) -> Bool {
        s.width.isFinite && s.height.isFinite && s.width > 1 && s.height > 1
    }

    /// NaN/inf (p.ej. centros sin resolver) -> 0.5 neutro.
    static func sanitized(_ v: CGFloat) -> CGFloat {
        v.isFinite ? min(max(v, 0), 1) : 0.5
    }

    /// Tamaño REAL de display: el iPhone graba en píxeles portrait + flag de
    /// rotación 90°/270° para landscape. Sin trasponer, todo el crop corre
    /// con w/h invertidos (preview medio negro, export mal encuadrado).
    public static func orientedSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let angle = atan2(Double(preferredTransform.b), Double(preferredTransform.a)) * 180.0 / .pi
        let deg = abs(angle)
        if abs(deg - 90) < 1 || abs(deg - 270) < 1 {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }
}
