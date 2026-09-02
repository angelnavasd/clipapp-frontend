import SwiftUI

public struct TextTimelineEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedWord: WordTimestamp? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header del Timeline
            HStack {
                Text("EDICIÓN GUIADA POR TEXTO")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.gray)
                    .tracking(1)

                Spacer()

                if let count = viewModel.selectedClip?.cutSegments.count, count > 0 {
                    Text("\(count) cortes aplicados")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            // Barra Filmstrip Visual Simulada
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 24)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange, lineWidth: 1.5)
            )

            // Instrucción rápida
            Text("Toca una palabra para eliminarla y cortar ese tiempo del video:")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            // Bloque de Palabras Interactivas
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 6) {
                    ForEach(currentClipWords(), id: \.id) { word in
                        Button(action: {
                            selectedWord = word
                            viewModel.triggerHapticFeedback(type: .light)
                        }) {
                            Text(word.word)
                                .font(.system(size: 14, weight: word.isFiller == true ? .bold : .medium))
                                .foregroundColor(colorForWord(word))
                                .strikethrough(word.isDeleted, color: .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(backgroundForWord(word))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 120)

            // Panel de Acción para Palabra Seleccionada
            if let word = selectedWord, !word.isDeleted {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Palabra: \"\(word.word)\"")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text("Tiempo: \(String(format: "%.2f", word.start))s - \(String(format: "%.2f", word.end))s • \(String(format: "%.1f", word.db ?? -20)) dB")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.deleteWordFromCurrentClip(word)
                        selectedWord = nil
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text("Cortar del video")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func currentClipWords() -> [WordTimestamp] {
        guard let clip = viewModel.selectedClip, let transcript = viewModel.transcriptPayload else {
            return []
        }
        return transcript.words.filter {
            $0.start >= (clip.timeRange.start - 0.2) && $0.end <= (clip.timeRange.end + 0.2)
        }
    }

    private func colorForWord(_ word: WordTimestamp) -> Color {
        if word.isDeleted {
            return Color.gray.opacity(0.5)
        }
        if word.isFiller == true {
            return Color.red.opacity(0.9)
        }
        if selectedWord?.id == word.id {
            return Color.yellow
        }
        return Color.white
    }

    private func backgroundForWord(_ word: WordTimestamp) -> Color {
        if word.isDeleted {
            return Color.red.opacity(0.1)
        }
        if selectedWord?.id == word.id {
            return Color.orange.opacity(0.3)
        }
        if word.isFiller == true {
            return Color.red.opacity(0.2)
        }
        return Color.white.opacity(0.08)
    }
}

// Helper para diseño tipo Flex / Flow de palabras
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height = y + rowHeight
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
