import SwiftUI

public struct ColorFilterPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILTROS Y COLORIMETRÍA")
                .font(.system(size: 11, weight: .black))
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
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
