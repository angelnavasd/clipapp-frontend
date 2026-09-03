import SwiftUI

public struct TranscriptDrawerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    var onSeek: ((Double) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel, onSeek: ((Double) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSeek = onSeek
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.11)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Opciones Rápidas de Subtítulo (Estilo y Tamaño)
                        styleAndSizeSelectors()

                        // Lista de Frases / Story Beats con Timestamps
                        phrasesSection()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Subtítulos y Guion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)
                }
            }
            #endif
        }
    }

    // MARK: - Selectores de Estilo y Tamaño
    @ViewBuilder
    private func styleAndSizeSelectors() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ESTILO DE SUBTÍTULOS")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.gray)
                .tracking(1)

            // Selector de Estilo
            HStack(spacing: 8) {
                ForEach(SubtitleStyle.allCases) { style in
                    let isSelected = (viewModel.selectedSubtitleStyle == style)
                    Button(action: {
                        viewModel.selectedSubtitleStyle = style
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Text(style.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.orange : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }

            // Selector de Tamaño
            HStack(spacing: 12) {
                Text("Tamaño:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)

                ForEach(SubtitleFontSize.allCases) { size in
                    let isSelected = (viewModel.selectedSubtitleSize == size)
                    Button(action: {
                        viewModel.selectedSubtitleSize = size
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Text(size.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isSelected ? .black : .white)
                            .frame(width: 32, height: 28)
                            .background(isSelected ? Color.white : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Spacer()

                if let cuts = viewModel.selectedClip?.cutSegments.count, cuts > 0 {
                    Text("\(cuts) cortes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sección de Frases Estructuradas
    @ViewBuilder
    private func phrasesSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LÍNEA NARRATIVA (TOCA UNA PALABRA PARA CORTARLA)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.gray)
                    .tracking(1)
                Spacer()
            }

            let groups = groupWordsIntoPhrases()

            if groups.isEmpty {
                Text("No hay palabras detectadas para este clip.")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .padding(.vertical, 10)
            } else {
                ForEach(groups, id: \.id) { group in
                    phraseCard(group: group)
                }
            }
        }
    }

    @ViewBuilder
    private func phraseCard(group: PhraseGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header con Timestamp y Botón de Play
            HStack {
                Button(action: {
                    onSeek?(group.start)
                    viewModel.triggerHapticFeedback(type: .light)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("\(formatTime(group.start)) - \(formatTime(group.end))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                }

                if let role = group.role {
                    Text(role.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.yellow.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()
            }

            // Palabras de la frase en formato de lectura continuo
            FlowLayout(spacing: 6) {
                ForEach(group.words, id: \.id) { word in
                    Button(action: {
                        viewModel.deleteWordFromCurrentClip(word)
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Text(word.word)
                            .font(.system(size: 13, weight: word.isDeleted ? .regular : .medium))
                            .foregroundColor(word.isDeleted ? .red.opacity(0.7) : .white)
                            .strikethrough(word.isDeleted, color: .red)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                word.isDeleted
                                    ? Color.red.opacity(0.15)
                                    : Color.white.opacity(0.06)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers de Agrupación
    struct PhraseGroup: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let role: String?
        let words: [WordTimestamp]
    }

    private func groupWordsIntoPhrases() -> [PhraseGroup] {
        guard let clip = viewModel.selectedClip, let payload = viewModel.transcriptPayload else {
            return []
        }

        // Si el clip tiene storyBeats, usar cada beat como una frase estructurada
        if let beats = clip.storyBeats, !beats.isEmpty {
            return beats.enumerated().map { index, beat in
                let beatWords = payload.words.filter { w in
                    w.start >= (beat.start - 0.2) && w.end <= (beat.end + 0.2)
                }
                return PhraseGroup(
                    id: "beat_\(index)_\(beat.start)",
                    start: beat.start,
                    end: beat.end,
                    role: beat.role,
                    words: beatWords.isEmpty ? [WordTimestamp(word: beat.text, start: beat.start, end: beat.end)] : beatWords
                )
            }
        }

        // Fallback: agrupar palabras en fragmentos de ~5 a 7 palabras
        let clipWords = payload.words.filter { w in
            w.start >= clip.timeRange.start && w.end <= clip.timeRange.end
        }

        guard !clipWords.isEmpty else { return [] }

        var result: [PhraseGroup] = []
        let chunkSize = 6
        var i = 0

        while i < clipWords.count {
            let chunk = Array(clipWords[i..<min(i + chunkSize, clipWords.count)])
            if let first = chunk.first, let last = chunk.last {
                result.append(
                    PhraseGroup(
                        id: "chunk_\(i)",
                        start: first.start,
                        end: last.end,
                        role: nil,
                        words: chunk
                    )
                )
            }
            i += chunkSize
        }

        return result
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
