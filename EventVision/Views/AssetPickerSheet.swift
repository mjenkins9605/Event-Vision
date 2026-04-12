import SwiftUI

struct AssetPickerSheet: View {
    @EnvironmentObject var assetStore: AssetStore
    @Binding var selectedAsset: ImageAsset?
    @Binding var presetWidth: Float?
    @Binding var presetHeight: Float?
    @Environment(\.dismiss) var dismiss
    @State private var detailAsset: ImageAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            Group {
                if assetStore.assets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("No assets imported yet.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("Go to Asset Library from the home page to import images.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(assetStore.assets) { asset in
                                // Main asset (default size)
                                PickerGridItem(
                                    asset: asset,
                                    assetStore: assetStore,
                                    isSelected: selectedAsset?.id == asset.id && presetWidth == nil,
                                    sizeLabel: asset.physicalWidthMeters != nil
                                        ? "\(MeasurementFormatter.feetInches(asset.physicalWidthMeters!)) \u{00D7} \(MeasurementFormatter.feetInches(asset.physicalHeightMeters ?? 0))"
                                        : nil,
                                    onTap: {
                                        selectedAsset = asset
                                        presetWidth = nil
                                        presetHeight = nil
                                        dismiss()
                                    },
                                    onInfo: {
                                        detailAsset = asset
                                    }
                                )

                                // Presets for this asset
                                ForEach(assetStore.presets(for: asset.id)) { preset in
                                    PickerGridItem(
                                        asset: asset,
                                        assetStore: assetStore,
                                        isSelected: selectedAsset?.id == asset.id
                                            && presetWidth == preset.widthMeters
                                            && presetHeight == preset.heightMeters,
                                        sizeLabel: "\(MeasurementFormatter.feetInches(preset.widthMeters)) \u{00D7} \(MeasurementFormatter.feetInches(preset.heightMeters))",
                                        onTap: {
                                            selectedAsset = asset
                                            presetWidth = preset.widthMeters
                                            presetHeight = preset.heightMeters
                                            dismiss()
                                        },
                                        onInfo: {
                                            detailAsset = asset
                                        }
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Assets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $detailAsset) { asset in
                NavigationView {
                    AssetDetailView(asset: asset)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { detailAsset = nil }
                            }
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Picker Grid Item

private struct PickerGridItem: View {
    let asset: ImageAsset
    let assetStore: AssetStore
    let isSelected: Bool
    let sizeLabel: String?
    let onTap: () -> Void
    let onInfo: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )

                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(6)
                            .padding(4)
                    } else {
                        ProgressView()
                            .tint(.gray)
                    }

                    // Info button
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onInfo) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(6)
                        }
                        Spacer()
                    }

                    // Size badge for presets
                    if let sizeLabel = sizeLabel {
                        Text(sizeLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.85))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }

                Text(asset.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if sizeLabel != nil {
                    Text("Preset")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            image = assetStore.loadImage(for: asset)
        }
    }
}
