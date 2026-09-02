import SwiftUI

public struct ProcessingView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pulseAnimation: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Animated Glowing Core
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(pulseAnimation ? 0.25 : 0.08))
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulseAnimation ? 1.15 : 0.95)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseAnimation)

                    Circle()
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                        .frame(width: 110, height: 110)

                    Image(systemName: iconForStep(viewModel.currentProcessingStep))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .onAppear {
                    pulseAnimation = true
                }

                VStack(spacing: 10) {
                    Text(viewModel.currentProcessingStep.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("Procesamiento acelerado en Apple Neural Engine & Gemini Flash")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                // Stepper Visual
                VStack(spacing: 16) {
                    ForEach(ProcessingStep.allCases, id: \.self) { step in
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(stepIndicatorColor(step))
                                    .frame(width: 28, height: 28)

                                if step.rawValue < viewModel.currentProcessingStep.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.black)
                                } else if step == viewModel.currentProcessingStep {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 10, height: 10)
                                }
                            }

                            Text(stepTitle(step))
                                .font(.system(size: 15, weight: step == viewModel.currentProcessingStep ? .bold : .medium))
                                .foregroundColor(step.rawValue <= viewModel.currentProcessingStep.rawValue ? .white : .gray.opacity(0.6))

                            Spacer()

                            if step == viewModel.currentProcessingStep {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                // Barra de Progreso Global
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.processingProgress)
                        .tint(.orange)
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)

                    HStack {
                        Text("Progreso estimado")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(viewModel.processingProgress * 100))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    private func iconForStep(_ step: ProcessingStep) -> String {
        switch step {
        case .extractingAudio: return "waveform"
        case .transcribingOnDevice: return "cpu"
        case .analyzingWithGemini: return "sparkles"
        case .preparingPreviews: return "film"
        }
    }

    private func stepTitle(_ step: ProcessingStep) -> String {
        switch step {
        case .extractingAudio: return "1. Extracción de audio PCM"
        case .transcribingOnDevice: return "2. Transcripción On-Device (WhisperKit)"
        case .analyzingWithGemini: return "3. Detección de Hooks (Gemini Flash)"
        case .preparingPreviews: return "4. Generación de Clips 9:16"
        }
    }

    private func stepIndicatorColor(_ step: ProcessingStep) -> Color {
        if step.rawValue < viewModel.currentProcessingStep.rawValue {
            return Color.green
        } else if step == viewModel.currentProcessingStep {
            return Color.orange
        } else {
            return Color(white: 0.2)
        }
    }
}
