import SwiftUI

/// Overlay de Zona Segura que representa los elementos de la interfaz de TikTok, Reels y Shorts
public struct SafeZoneOverlayView: View {
    public init() {}

    public var body: some View {
        ZStack {
            // Contorno general de zona segura
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    Color.yellow.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 40)

            // Simulación de Botones Laterales Derechos (Like, Comment, Share, Audio Disc)
            VStack(spacing: 20) {
                Spacer()
                ForEach(["heart.fill", "ellipsis.bubble.fill", "bookmark.fill", "arrowshape.turn.up.right.fill"], id: \.self) { icon in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.8))
                            )
                        Text("12k")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // Disco de audio giratorio
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
            .padding(.bottom, 90)

            // Simulación de Descripción y Username Inferior
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                HStack(spacing: 6) {
                    Text("@creador")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("• Seguir")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                }

                Text("Zona tapada por la descripción del video en Reels y TikTok...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)
            .padding(.bottom, 30)

            // Tag indicador de Safe Zone
            VStack {
                Text("⚠️ ZONA SEGURA (TIKTOK / REELS)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.top, 12)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}
