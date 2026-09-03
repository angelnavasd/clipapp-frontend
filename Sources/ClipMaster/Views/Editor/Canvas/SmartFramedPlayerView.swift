import SwiftUI
import AVFoundation

#if os(iOS)
public struct SmartFramedPlayerView: View {
    public let player: AVPlayer
    public let mode: FramingMode
    public let speakerCenterX: CGFloat
    public let speakerCenterY: CGFloat
    public let cornerRadius: CGFloat
    /// Tamaño natural del source (para igualar la matemática del export). nil = asumir 16:9 (legacy).
    public let sourceSize: CGSize?
    public let speakerFaceWidth: CGFloat?

    public init(
        player: AVPlayer,
        mode: FramingMode = .autoFaceTrack,
        speakerCenterX: CGFloat = 0.5,
        speakerCenterY: CGFloat = 0.5,
        cornerRadius: CGFloat = 20,
        sourceSize: CGSize? = nil,
        speakerFaceWidth: CGFloat? = nil
    ) {
        self.player = player
        self.mode = mode
        self.speakerCenterX = speakerCenterX
        self.speakerCenterY = speakerCenterY
        self.cornerRadius = cornerRadius
        self.sourceSize = sourceSize
        self.speakerFaceWidth = speakerFaceWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let containerHeight = geo.size.height

            ZStack {
                Color.black

                switch mode {
                case .autoFaceTrack:
                    autoFaceTrackLayer(containerWidth: containerWidth, containerHeight: containerHeight)

                case .splitScreen:
                    splitScreenLayer(containerWidth: containerWidth, containerHeight: containerHeight)

                case .blurredBackground:
                    blurredBackgroundLayer(containerWidth: containerWidth, containerHeight: containerHeight)

                case .manualCrop:
                    autoFaceTrackLayer(containerWidth: containerWidth, containerHeight: containerHeight, customCenterX: speakerCenterX)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    // MARK: - Modo Principal: Auto Face-Track (F4: misma fórmula que el export)
    @ViewBuilder
    private func autoFaceTrackLayer(containerWidth: CGFloat, containerHeight: CGFloat, customCenterX: CGFloat? = nil) -> some View {
        let targetX = customCenterX ?? speakerCenterX
        let center = CGPoint(x: targetX, y: speakerCenterY)

        if let src = sourceSize {
            // Ruta F4: layout idéntico al export vía FaceCropCalculator
            let layout = FaceCropCalculator.previewLayout(
                containerSize: CGSize(width: containerWidth, height: containerHeight),
                sourceSize: src,
                center: center,
                faceWidth: speakerFaceWidth
            )
            RawPlayerView(player: player, videoGravity: .resizeAspect)
                .frame(width: layout.size.width, height: layout.size.height)
                .offset(x: layout.offset.width, y: layout.offset.height)
                .frame(width: containerWidth, height: containerHeight)
                .clipped()
        } else {
            // Legacy: asumir 16:9 (sin sourceSize conocido)
            let videoHeight = containerHeight
            let videoWidth = containerHeight * (16.0 / 9.0)

            // Calcular desplazamiento para que el rostro quede centrado en el medio de la pantalla
            let rawOffset = videoWidth * (0.5 - targetX)
            let maxShift = max(0, (videoWidth - containerWidth) / 2.0)
            let clampedOffset = max(-maxShift, min(maxShift, rawOffset))

            RawPlayerView(player: player, videoGravity: .resizeAspectFill)
                .frame(width: videoWidth, height: videoHeight)
                .offset(x: clampedOffset)
                .frame(width: containerWidth, height: containerHeight)
                .clipped()
        }
    }

    // MARK: - Split-Screen real (WYSIWYG con el export: pantalla arriba + cara abajo)
    @ViewBuilder
    private func splitScreenLayer(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        if let src = sourceSize, src.width > 1, src.height > 1 {
            splitScreenLayers(src: src, containerWidth: containerWidth, containerHeight: containerHeight)
        } else {
            // Sin tamaño real: caer al crop simple (mejor que negro)
            autoFaceTrackLayer(containerWidth: containerWidth, containerHeight: containerHeight)
        }
    }

    @ViewBuilder
    private func splitScreenLayers(src: CGSize, containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        let split = FaceCropCalculator.splitFraction
        let topH = containerHeight * split
        let botH = containerHeight - topH
        let center = CGPoint(x: speakerCenterX, y: speakerCenterY)

        ZStack(alignment: .topLeading) {
            Color.black.frame(width: containerWidth, height: containerHeight)

            // Zona superior: pantalla ajustada al ancho, pegada arriba (igual que export)
            let topK = containerWidth / src.width
            RawPlayerView(player: player, videoGravity: .resizeAspect)
                .frame(width: src.width * topK, height: src.height * topK)
                .frame(width: containerWidth, height: topH, alignment: .top)
                .clipped()

            // Zona inferior: crop de la webcam llenando su zona (igual que export)
            let zoneAspect = containerWidth / botH
            let crop = FaceCropCalculator.splitBottomCropRect(sourceSize: src, center: center, targetAspect: zoneAspect)
            let botK = containerWidth / crop.width
            ZStack(alignment: .topLeading) {
                RawPlayerView(player: player, videoGravity: .resizeAspect)
                    .frame(width: src.width * botK, height: src.height * botK)
                    .offset(x: -crop.origin.x * botK, y: -crop.origin.y * botK)
            }
            .frame(width: containerWidth, height: botH, alignment: .topLeading)
            .clipped()
            .offset(y: topH)

            // Divisor (igual que el export: en el punto de split)
            Rectangle()
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .frame(width: containerWidth, height: 4)
                .offset(y: topH - 2)
        }
        .frame(width: containerWidth, height: containerHeight)
        .clipped()
    }

    // MARK: - Modo Secundario: Fondo Cinemático (Video 16:9 completo al centro)
    @ViewBuilder
    private func blurredBackgroundLayer(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: containerWidth, height: containerHeight)

            let fgHeight = containerWidth * (9.0 / 16.0)
            RawPlayerView(player: player, videoGravity: .resizeAspect)
                .frame(width: containerWidth, height: fgHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.6), radius: 16)
        }
        .frame(width: containerWidth, height: containerHeight)
        .clipped()
    }
}

/// Envoltorio UIViewRepresentable para AVPlayerLayer de alto rendimiento
public struct RawPlayerView: UIViewRepresentable {
    public let player: AVPlayer
    public var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    public init(player: AVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.player = player
        self.videoGravity = videoGravity
    }

    public func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    public func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

public final class PlayerContainerUIView: UIView {
    public let playerLayer = AVPlayerLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
#else
public struct SmartFramedPlayerView: View {
    public init(player: Any? = nil, mode: FramingMode = .autoFaceTrack, speakerCenterX: CGFloat = 0.5, speakerCenterY: CGFloat = 0.5, cornerRadius: CGFloat = 20, sourceSize: CGSize? = nil, speakerFaceWidth: CGFloat? = nil) {}
    public var body: some View { EmptyView() }
}
#endif
