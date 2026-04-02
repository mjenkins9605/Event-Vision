import Foundation
import UIKit

class AssetStore: ObservableObject {
    @Published var assets: [ImageAsset] = []
    @Published var presets: [AssetPreset] = []

    private let directory: URL
    private let manifestURL: URL
    private let presetsURL: URL
    private let imageCache = NSCache<NSUUID, UIImage>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("EventVision/Assets", isDirectory: true)
        manifestURL = directory.appendingPathComponent("assets.json")
        presetsURL = directory.appendingPathComponent("presets.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        loadManifest()
        loadPresets()
    }

    // MARK: - Import

    func importImage(from image: UIImage, name: String) -> ImageAsset {
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = directory.appendingPathComponent(filename)

        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL)
        }

        let asset = ImageAsset(
            name: name,
            filename: filename,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale)
        )

        assets.append(asset)
        assets.sort { $0.dateAdded > $1.dateAdded }
        saveManifest()
        return asset
    }

    // MARK: - Load Image

    func loadImage(for asset: ImageAsset) -> UIImage? {
        let key = asset.id as NSUUID
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let fileURL = directory.appendingPathComponent(asset.filename)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        let decodedCost: Int
        if let cgImage = image.cgImage {
            decodedCost = cgImage.bytesPerRow * cgImage.height
        } else {
            decodedCost = data.count
        }
        imageCache.setObject(image, forKey: key, cost: decodedCost)
        return image
    }

    // MARK: - Update

    func updateAsset(_ asset: ImageAsset) {
        if let idx = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[idx] = asset
            saveManifest()
        }
    }

    // MARK: - Delete

    func deleteAsset(_ asset: ImageAsset) {
        let fileURL = directory.appendingPathComponent(asset.filename)
        try? FileManager.default.removeItem(at: fileURL)
        imageCache.removeObject(forKey: asset.id as NSUUID)
        assets.removeAll { $0.id == asset.id }
        saveManifest()
        // Cascade-delete presets for this asset
        presets.removeAll { $0.assetID == asset.id }
        savePresets()
    }

    // MARK: - Presets

    func addPreset(_ preset: AssetPreset) {
        presets.append(preset)
        savePresets()
    }

    func deletePreset(_ preset: AssetPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func presets(for assetID: UUID) -> [AssetPreset] {
        presets.filter { $0.assetID == assetID }
    }

    // MARK: - Persistence

    private func saveManifest() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(assets) {
            try? data.write(to: manifestURL)
        }
    }

    private func loadManifest() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL),
              let loaded = try? decoder.decode([ImageAsset].self, from: data) else {
            return
        }
        assets = loaded.sorted { $0.dateAdded > $1.dateAdded }
    }

    private func savePresets() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(presets) {
            try? data.write(to: presetsURL)
        }
    }

    private func loadPresets() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: presetsURL),
              let loaded = try? decoder.decode([AssetPreset].self, from: data) else {
            return
        }
        presets = loaded
    }
}
