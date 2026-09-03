import SwiftUI

public struct SplashScreenView: View {
    var onFinished: () -> Void
    @State private var isAnimating: Bool = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Glow ambiental de fondo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.25), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(isAnimating ? 1.2 : 0.9)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 24) {
                // Icono Central
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 110, height: 110)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )

                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(scale)
                .opacity(opacity)

                // Tipografía y Branding
                VStack(spacing: 8) {
                    Text("CLIPMASTER")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(3)

                    Text("AI VIDEO SHORTS ENGINE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange.opacity(0.85))
                        .tracking(2)
                }
                .opacity(opacity)
            }

            // Indicador inferior sutil
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("On-Device AI Ready")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 40)
                .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                self.scale = 1.0
                self.opacity = 1.0
                self.isAnimating = true
            }

            // Transición automática al home tras 1.4 segundos
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    onFinished()
                }
            }
        }
    }
}
