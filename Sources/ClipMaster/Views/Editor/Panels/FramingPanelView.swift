import SwiftUI

public struct FramingPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MODO DE ENCUADRE 9:16")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.gray)
                .tracking(1)

            // Selector de Modos
            HStack(spacing: 10) {
                ForEach(FramingMode.allCases, id: \.id) { mode in
                    Button(action: {
                        viewModel.selectedFramingMode = mode
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 20))
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(viewModel.selectedFramingMode == mode ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            viewModel.selectedFramingMode == mode
                                ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            // Selector de Ubicación de la Webcam para Split-Screen
            if viewModel.selectedFramingMode == .splitScreen {
                VStack(alignment: .leading, spacing: 10) {
                    Text("UBICACIÓN DE TU WEBCAM")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.gray)
                        .tracking(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(WebcamCorner.allCases) { corner in
                                Button(action: {
                                    viewModel.setWebcamCorner(corner)
                                    viewModel.triggerHapticFeedback(type: .light)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: corner.icon)
                                            .font(.system(size: 13))
                                        Text(corner.rawValue)
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .foregroundColor(viewModel.selectedWebcamCorner == corner ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.selectedWebcamCorner == corner
                                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }

            // Descripción del Modo Activo
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))

                Text(descriptionForMode(viewModel.selectedFramingMode))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func descriptionForMode(_ mode: FramingMode) -> String {
        switch mode {
        case .autoFaceTrack:
            return "Visión artificial (Vision Framework) detecta y sigue la cara del orador con suavizado cinemático Lerp."
        case .splitScreen:
            return "Divide el video en 2 tomas: pantalla de la computadora arriba (55%) y webcam con rostro centrado abajo (45%)."
        case .blurredBackground:
            return "Pantalla completa nítida al centro con fondo desenfocado (ideal para leer código y tutoriales de PC)."
        case .manualCrop:
            return "Ajusta la posición horizontal y zoom libremente con gestos en pantalla."
        }
    }
}
