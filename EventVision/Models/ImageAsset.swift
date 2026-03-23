import Foundation

// MARK: - Image Asset

struct ImageAsset: Codable, Identifiable {
    let id: UUID
    var name: String
    let filename: String
    let dateAdded: Date
    let originalWidth: Int
    let originalHeight: Int

    // Vendor info
    var vendorName: String?
    var vendorAddress: String?
    var vendorPhone: String?
    var notes: String?
    var quotes: [VendorQuote]?

    // Physical dimensions (real-world size: W x H x D)
    var physicalWidthMeters: Float?
    var physicalHeightMeters: Float?
    var physicalDepthMeters: Float?

    var aspectRatio: Float {
        Float(originalWidth) / Float(max(originalHeight, 1))
    }

    init(name: String, filename: String, width: Int, height: Int) {
        self.id = UUID()
        self.name = name
        self.filename = filename
        self.dateAdded = Date()
        self.originalWidth = width
        self.originalHeight = height
        self.vendorName = nil
        self.vendorAddress = nil
        self.vendorPhone = nil
        self.notes = nil
        self.quotes = nil
        self.physicalWidthMeters = nil
        self.physicalHeightMeters = nil
        self.physicalDepthMeters = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filename = try container.decode(String.self, forKey: .filename)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        originalWidth = try container.decode(Int.self, forKey: .originalWidth)
        originalHeight = try container.decode(Int.self, forKey: .originalHeight)
        vendorName = try container.decodeIfPresent(String.self, forKey: .vendorName)
        vendorAddress = try container.decodeIfPresent(String.self, forKey: .vendorAddress)
        vendorPhone = try container.decodeIfPresent(String.self, forKey: .vendorPhone)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        quotes = try container.decodeIfPresent([VendorQuote].self, forKey: .quotes)
        // Support old "physicalLengthMeters" key as fallback for width
        physicalWidthMeters = try container.decodeIfPresent(Float.self, forKey: .physicalWidthMeters)
            ?? container.decodeIfPresent(Float.self, forKey: .physicalLengthMeters)
        physicalHeightMeters = try container.decodeIfPresent(Float.self, forKey: .physicalHeightMeters)
        physicalDepthMeters = try container.decodeIfPresent(Float.self, forKey: .physicalDepthMeters)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, filename, dateAdded, originalWidth, originalHeight
        case vendorName, vendorAddress, vendorPhone, notes, quotes
        case physicalWidthMeters, physicalHeightMeters, physicalDepthMeters
        case physicalLengthMeters // legacy read-only key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(filename, forKey: .filename)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(originalWidth, forKey: .originalWidth)
        try container.encode(originalHeight, forKey: .originalHeight)
        try container.encodeIfPresent(vendorName, forKey: .vendorName)
        try container.encodeIfPresent(vendorAddress, forKey: .vendorAddress)
        try container.encodeIfPresent(vendorPhone, forKey: .vendorPhone)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(quotes, forKey: .quotes)
        try container.encodeIfPresent(physicalWidthMeters, forKey: .physicalWidthMeters)
        try container.encodeIfPresent(physicalHeightMeters, forKey: .physicalHeightMeters)
        try container.encodeIfPresent(physicalDepthMeters, forKey: .physicalDepthMeters)
        // physicalLengthMeters is legacy — never written
    }
}

// MARK: - Vendor Quote

struct VendorQuote: Codable, Identifiable {
    let id: UUID
    var amount: String
    var note: String
    let dateAdded: Date

    init(amount: String = "", note: String = "") {
        self.id = UUID()
        self.amount = amount
        self.note = note
        self.dateAdded = Date()
    }
}

// MARK: - Placed Prop

struct PlacedProp: Codable, Identifiable {
    let id: UUID
    let assetID: UUID
    var transform: CodableMatrix4x4
    var widthMeters: Float
    var heightMeters: Float
    var depthMeters: Float
    var surfaceID: UUID?

    init(assetID: UUID, transform: CodableMatrix4x4, widthMeters: Float, heightMeters: Float, depthMeters: Float = 0, surfaceID: UUID? = nil) {
        self.id = UUID()
        self.assetID = assetID
        self.transform = transform
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.depthMeters = depthMeters
        self.surfaceID = surfaceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        assetID = try container.decode(UUID.self, forKey: .assetID)
        transform = try container.decode(CodableMatrix4x4.self, forKey: .transform)
        widthMeters = try container.decode(Float.self, forKey: .widthMeters)
        heightMeters = try container.decode(Float.self, forKey: .heightMeters)
        depthMeters = try container.decodeIfPresent(Float.self, forKey: .depthMeters) ?? 0
        surfaceID = try container.decodeIfPresent(UUID.self, forKey: .surfaceID)
    }
}

// MARK: - Asset Preset

struct AssetPreset: Codable, Identifiable {
    let id: UUID
    let assetID: UUID
    var name: String
    var widthMeters: Float
    var heightMeters: Float
    let dateCreated: Date

    init(assetID: UUID, name: String, widthMeters: Float, heightMeters: Float) {
        self.id = UUID()
        self.assetID = assetID
        self.name = name
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.dateCreated = Date()
    }
}
