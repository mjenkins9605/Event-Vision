import Foundation
import RoomPlan

class ScanStore: ObservableObject {
    @Published var scans: [SavedScan] = []

    private let directory: URL
    private var isLoaded = false
    private var pendingMutations: [() -> Void] = []

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("EventVision/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAllAsync()
    }

    // MARK: - Save

    func save(_ scan: SavedScan, room: CapturedRoom? = nil) {
        // Always persist to disk immediately
        let fileURL = directory.appendingPathComponent("\(scan.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(scan) {
            try? data.write(to: fileURL)
        }

        if let room = room {
            let usdzURL = directory.appendingPathComponent("\(scan.id.uuidString).usdz")
            try? room.export(to: usdzURL)
        }

        // Defer in-memory update if initial load hasn't completed
        if !isLoaded {
            pendingMutations.append { [weak self] in
                self?.applyUpsert(scan)
            }
            return
        }

        applyUpsert(scan)
    }

    private func applyUpsert(_ scan: SavedScan) {
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

        if !isLoaded {
            let scanID = scan.id
            pendingMutations.append { [weak self] in
                self?.scans.removeAll { $0.id == scanID }
            }
            return
        }

        scans.removeAll { $0.id == scan.id }
    }

    // MARK: - Load All

    private func loadAllAsync() {
        let dir = directory
        DispatchQueue.global(qos: .userInitiated).async {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                return
            }

            var loaded: [SavedScan] = []
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let scan = try? decoder.decode(SavedScan.self, from: data) {
                    loaded.append(scan)
                }
            }

            let sorted = loaded.sorted { $0.date > $1.date }
            DispatchQueue.main.async {
                self.scans = sorted
                self.isLoaded = true
                for mutation in self.pendingMutations {
                    mutation()
                }
                self.pendingMutations.removeAll()
            }
        }
    }
}
