import SwiftUI

public struct CaptionsPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PLANTILLAS DE SUBTÍTULOS DINÁMICOS")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.gray)
                .tracking(1)

            // Selector de Estilos
            HStack(spacing: 10) {
                ForEach(SubtitleStyle.allCases, id: \.id) { style in
                    Button(action: {
                        viewModel.selectedSubtitleStyle = style
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        VStack(spacing: 6) {
                            Text(style.rawValue)
                                .font(.system(size: 13, weight: .bold))
                            Text(style.previewDescription)
                                .font(.system(size: 9))
                                .opacity(0.8)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundColor(viewModel.selectedSubtitleStyle == style ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 6)
                        .background(
                            viewModel.selectedSubtitleStyle == style
                                ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            // Selector de Tamaño (S, M, L)
            HStack {
                Text("Tamaño:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(SubtitleFontSize.allCases, id: \.id) { size in
                        Button(action: {
                            viewModel.selectedSubtitleSize = size
                            viewModel.triggerHapticFeedback(type: .light)
                        }) {
                            Text(size.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(viewModel.selectedSubtitleSize == size ? .black : .white)
                                .frame(width: 38, height: 32)
                                .background(viewModel.selectedSubtitleSize == size ? Color.white : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.top, 4)

            // Tip sobre arrastre
            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("Puedes arrastrar los subtítulos directamente sobre el canvas para cambiar su posición vertical.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
