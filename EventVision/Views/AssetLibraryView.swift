import SwiftUI
import PhotosUI

struct AssetLibraryView: View {
    @EnvironmentObject var assetStore: AssetStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showNamePrompt = false
    @State private var newAssetName = ""
    @State private var pendingImage: UIImage?
    @State private var assetToDelete: ImageAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if assetStore.assets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Assets Yet")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Import banners, signage, and decor images to place in your scans.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(assetStore.assets) { asset in
                            NavigationLink {
                                AssetDetailView(asset: asset)
                            } label: {
                                AssetGridItem(asset: asset, assetStore: assetStore) {
                                    assetToDelete = asset
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color.black)
            }
        }
        .navigationTitle("Asset Library")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pendingImage = image
                    newAssetName = ""
                    showNamePrompt = true
                }
                selectedPhoto = nil
            }
        }
        .alert("Name This Asset", isPresented: $showNamePrompt) {
            TextField("e.g. Main Banner", text: $newAssetName)
            Button("Save") {
                if let image = pendingImage {
                    let trimmed = newAssetName.trimmingCharacters(in: .whitespaces)
                    let name = trimmed.isEmpty ? "Untitled Asset" : trimmed
                    _ = assetStore.importImage(from: image, name: name)
                    pendingImage = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImage = nil
            }
        } message: {
            Text("Give this image a name so you can find it when placing props.")
        }
        .alert("Delete Asset", isPresented: Binding(
            get: { assetToDelete != nil },
            set: { if !$0 { assetToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let asset = assetToDelete {
                    assetStore.deleteAsset(asset)
                    assetToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                assetToDelete = nil
            }
        } message: {
            if let asset = assetToDelete {
                Text("Are you sure you want to delete \u{201C}\(asset.name)\u{201D}? This cannot be undone.")
            }
        }
    }
}

// MARK: - Grid Item

struct AssetGridItem: View {
    let asset: ImageAsset
    let assetStore: AssetStore
    let onDelete: () -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(1, contentMode: .fit)

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
            }

            Text(asset.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)

            if let w = asset.physicalWidthMeters, let h = asset.physicalHeightMeters {
                let dims = asset.physicalDepthMeters.map { d in
                    "\(MeasurementFormatter.feetInches(w)) \u{00D7} \(MeasurementFormatter.feetInches(h)) \u{00D7} \(MeasurementFormatter.feetInches(d))"
                } ?? "\(MeasurementFormatter.feetInches(w)) \u{00D7} \(MeasurementFormatter.feetInches(h))"
                Text(dims)
                    .font(.system(size: 9))
                    .foregroundColor(.blue)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            image = assetStore.loadImage(for: asset)
        }
    }
}
