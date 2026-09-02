import SwiftUI

public struct AudioVibePanelView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Auto-Ducking Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AUTO-DUCKING INTELIGENTE")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.gray)
                            .tracking(1)

                        Text("-18 dB")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text("Atenúa la música automáticamente cuando el orador habla.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                Toggle("", isOn: $viewModel.enableAutoDucking)
                    .tint(.orange)
                    .labelsHidden()
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Selector de Pistas Musicales
            VStack(alignment: .leading, spacing: 8) {
                Text("PISTA MUSICAL DE FONDO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.musicTracks, id: \.id) { track in
                            Button(action: {
                                viewModel.selectedMusicTrack = track
                                viewModel.triggerHapticFeedback(type: .light)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: track.id == "none" ? "speaker.slash.fill" : "music.note")
                                        .font(.system(size: 12))
                                    Text(track.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    if track.bpm > 0 {
                                        Text("\(track.bpm) BPM")
                                            .font(.system(size: 10))
                                            .opacity(0.7)
                                    }
                                }
                                .foregroundColor(viewModel.selectedMusicTrack?.id == track.id ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    viewModel.selectedMusicTrack?.id == track.id
                                        ? Color.yellow
                                        : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            // Selector de LUTs / Colorimetría
            VStack(alignment: .leading, spacing: 8) {
                Text("PRESETS DE COLOR (LUTs)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.lutPresets, id: \.id) { lut in
                            Button(action: {
                                viewModel.selectedLutPreset = lut
                                viewModel.triggerHapticFeedback(type: .light)
                            }) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: lut.thumbnailColor))
                                        .frame(width: 14, height: 14)

                                    Text(lut.name)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(viewModel.selectedLutPreset?.id == lut.id ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    viewModel.selectedLutPreset?.id == lut.id
                                        ? Color.white
                                        : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
