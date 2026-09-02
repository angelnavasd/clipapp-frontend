import SwiftUI

public struct ClipsFeedView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var activeCardIndex: Int = 0

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack {
                    Button(action: {
                        viewModel.navigationState = .home
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Nuevo Video")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                    }

                    Spacer()

                    Text("CLIPS SUGERIDOS")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .tracking(1)

                    Spacer()

                    // Placeholder simétrico para centrado
                    Text("Nuevo Video")
                        .font(.system(size: 15))
                        .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Feed / Carousel
                if let clips = viewModel.edlResponse?.clips, !clips.isEmpty {
                    TabView(selection: $activeCardIndex) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            ClipCardView(
                                clip: clip,
                                videoURL: viewModel.localVideoURL,
                                isActive: (index == activeCardIndex),
                                viewModel: viewModel,
                                onEdit: {
                                    viewModel.selectClipForEditing(clip)
                                },
                                onQuickExport: {
                                    viewModel.selectedClip = clip
                                    Task {
                                        await viewModel.exportCurrentClip()
                                    }
                                }
                            )
                            .tag(index)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    #else
                    .tabViewStyle(.automatic)
                    #endif
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No se encontraron clips virales en este segmento.")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
        }
        .overlay(
            Group {
                if viewModel.isExporting {
                    ZStack {
                        Color.black.opacity(0.8).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView(value: viewModel.exportProgress)
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(2.0)
                            Text("Renderizando Short en 1080x1920...")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(Int(viewModel.exportProgress * 100))%")
                                .foregroundColor(.orange)
                        }
                        .padding(32)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
        )
    }
}
