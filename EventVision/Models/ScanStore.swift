import Foundation
import RoomPlan

class ScanStore: ObservableObject {
    @Published var scans: [SavedScan] = []

    private let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("EventVision/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - Save

    func save(_ scan: SavedScan, room: CapturedRoom? = nil) {
        let fileURL = directory.appendingPathComponent("\(scan.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(scan) {
            try? data.write(to: fileURL)
        }

        // Export USDZ if we have the live CapturedRoom
        if let room = room {
            let usdzURL = directory.appendingPathComponent("\(scan.id.uuidString).usdz")
            try? room.export(to: usdzURL)
        }

        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[index] = scan
        } else {
            scans.append(scan)
            scans.sort { $0.date > $1.date }
        }
    }

    // MARK: - USDZ

    func usdzURL(for scan: SavedScan) -> URL? {
        let url = directory.appendingPathComponent("\(scan.id.uuidString).usdz")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Delete

    func delete(_ scan: SavedScan) {
        let fileURL = directory.appendingPathComponent("\(scan.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        let usdzFile = directory.appendingPathComponent("\(scan.id.uuidString).usdz")
        try? FileManager.default.removeItem(at: usdzFile)
        scans.removeAll { $0.id == scan.id }
    }

    // MARK: - Load All

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        var loaded: [SavedScan] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let scan = try? decoder.decode(SavedScan.self, from: data) {
                loaded.append(scan)
            }
        }

        scans = loaded.sorted { $0.date > $1.date }
    }
}
