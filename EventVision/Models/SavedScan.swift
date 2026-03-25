import Foundation
import simd
import RoomPlan

// MARK: - Saved Scan (top-level model)

struct SavedScan: Codable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    let walls: [SavedSurface]
    let doors: [SavedSurface]
    let windows: [SavedSurface]
    let openings: [SavedSurface]
    var placedProps: [PlacedProp]

    var totalSurfaces: Int {
        walls.count + doors.count + windows.count + openings.count
    }

    init(name: String, room: CapturedRoom) {
        self.id = UUID()
        self.name = name
        self.date = Date()
        self.walls = room.walls.map { SavedSurface(from: $0) }
        self.doors = room.doors.map { SavedSurface(from: $0) }
        self.windows = room.windows.map { SavedSurface(from: $0) }
        self.openings = room.openings.map { SavedSurface(from: $0) }
        self.placedProps = []
    }

    /// Create a scan with only placed props (no room geometry) for AR placement sessions.
    init(name: String, placedProps: [PlacedProp]) {
        self.id = UUID()
        self.name = name
        self.date = Date()
        self.walls = []
        self.doors = []
        self.windows = []
        self.openings = []
        self.placedProps = placedProps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        walls = try container.decode([SavedSurface].self, forKey: .walls)
        doors = try container.decode([SavedSurface].self, forKey: .doors)
        windows = try container.decode([SavedSurface].self, forKey: .windows)
        openings = try container.decode([SavedSurface].self, forKey: .openings)
        placedProps = try container.decodeIfPresent([PlacedProp].self, forKey: .placedProps) ?? []
    }
}

// MARK: - Saved Surface

struct SavedSurface: Codable, Identifiable {
    let id: UUID
    let dimensionsX: Float
    let dimensionsY: Float
    let dimensionsZ: Float
    let transform: CodableMatrix4x4

    var dimensions: simd_float3 {
        simd_float3(dimensionsX, dimensionsY, dimensionsZ)
    }

    var simdTransform: simd_float4x4 {
        transform.matrix
    }

    init(from surface: CapturedRoom.Surface) {
        self.id = surface.identifier
        self.dimensionsX = surface.dimensions.x
        self.dimensionsY = surface.dimensions.y
        self.dimensionsZ = surface.dimensions.z
        self.transform = CodableMatrix4x4(surface.transform)
    }
}

// MARK: - Codable simd_float4x4

struct CodableMatrix4x4: Codable {
    let columns: [[Float]]

    var matrix: simd_float4x4 {
        simd_float4x4(
            simd_float4(columns[0][0], columns[0][1], columns[0][2], columns[0][3]),
            simd_float4(columns[1][0], columns[1][1], columns[1][2], columns[1][3]),
            simd_float4(columns[2][0], columns[2][1], columns[2][2], columns[2][3]),
            simd_float4(columns[3][0], columns[3][1], columns[3][2], columns[3][3])
        )
    }

    init(_ m: simd_float4x4) {
        self.columns = [
            [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w],
            [m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w],
            [m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w],
            [m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w],
        ]
    }
}
