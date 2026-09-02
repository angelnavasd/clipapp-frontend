import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

/// Vista personalizada que recorta y encuadra dinámicamente un video 16:9 en un contenedor vertical 9:16
/// eliminando completamente las franjas negras y centrando el rostro del orador detectado con Vision.
public struct SmartFramedPlayerView: View {
    public let player: AVPlayer
    public let mode: FramingMode
    public let speakerCenterX: CGFloat
    public let speakerCenterY: CGFloat
    public var cornerRadius: CGFloat = 20

    public init(
        player: AVPlayer,
        mode: FramingMode = .autoFaceTrack,
        speakerCenterX: CGFloat = 0.5,
        speakerCenterY: CGFloat = 0.5,
        cornerRadius: CGFloat = 20
    ) {
        self.player = player
        self.mode = mode
        self.speakerCenterX = speakerCenterX
        self.speakerCenterY = speakerCenterY
        self.cornerRadius = cornerRadius
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
                    autoFaceTrackLayer(containerWidth: containerWidth, containerHeight: containerHeight, customCenterX: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    // MARK: - Modo 1: Auto Face-Track (Llenado vertical 9:16 centrado en el rostro)
    @ViewBuilder
    private func autoFaceTrackLayer(containerWidth: CGFloat, containerHeight: CGFloat, customCenterX: CGFloat? = nil) -> some View {
        // En video horizontal 16:9, la altura del video llena la altura del marco vertical:
        let videoHeight = containerHeight
        let videoWidth = containerHeight * (16.0 / 9.0)
        let overflow = max(0, videoWidth - containerWidth)

        let targetX = customCenterX ?? speakerCenterX
        // Calcular el desplazamiento para que targetX quede en el centro de la pantalla:
        let desiredOffset = (containerWidth / 2.0) - (videoWidth * targetX)
        // Limitar para nunca mostrar espacios vacíos en los laterales:
        let clampedOffset = min(0, max(-overflow, desiredOffset))

        RawPlayerView(player: player, videoGravity: .resizeAspectFill)
            .frame(width: videoWidth, height: videoHeight)
            .offset(x: clampedOffset + (overflow / 2.0))
            .frame(width: containerWidth, height: containerHeight)
            .clipped()
    }

    // MARK: - Modo 2: Split-Screen Apilado (Arriba: Cara ampliada / Abajo: Pantalla completa)
    @ViewBuilder
    private func splitScreenLayer(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            // Mitad Superior: Rostro ampliado en primer plano
            let topHeight = containerHeight * 0.44
            let topVideoWidth = topHeight * 2.5
            let topOverflow = max(0, topVideoWidth - containerWidth)
            let topOffset = min(0, max(-topOverflow, (containerWidth / 2.0) - (topVideoWidth * speakerCenterX)))

            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.14)
                RawPlayerView(player: player, videoGravity: .resizeAspectFill)
                    .frame(width: topVideoWidth, height: topHeight)
                    .offset(x: topOffset + (topOverflow / 2.0))
            }
            .frame(width: containerWidth, height: topHeight)
            .clipped()

            // Divisor estilizado
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            // Mitad Inferior: Pantalla completa ajustada al ancho
            let bottomHeight = containerHeight * 0.54
            ZStack {
                Color.black
                RawPlayerView(player: player, videoGravity: .resizeAspect)
                    .frame(width: containerWidth, height: bottomHeight)
            }
            .frame(width: containerWidth, height: bottomHeight)
            .clipped()
        }
    }

    // MARK: - Modo 3: Fondo Borroso (Pantalla completa al centro con desenfoque de ambiente)
    @ViewBuilder
    private func blurredBackgroundLayer(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        ZStack {
            // Capa de fondo difuminada
            RawPlayerView(player: player, videoGravity: .resizeAspectFill)
                .blur(radius: 30)
                .overlay(Color.black.opacity(0.45))
                .frame(width: containerWidth, height: containerHeight)

            // Capa frontal nítida (16:9 centrado para leer texto y código perfectamente)
            let fgHeight = containerWidth * (9.0 / 16.0)
            RawPlayerView(player: player, videoGravity: .resizeAspect)
                .frame(width: containerWidth, height: fgHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.6), radius: 16)
        }
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
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
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
    public init(player: Any? = nil, mode: FramingMode = .autoFaceTrack, speakerCenterX: CGFloat = 0.5, speakerCenterY: CGFloat = 0.5, cornerRadius: CGFloat = 20) {}
    public var body: some View { EmptyView() }
}
#endif
