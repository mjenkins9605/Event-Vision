import Foundation

enum CaptureMode: String, CaseIterable {
    case arScan = "AR Scan"
    case photo = "Photo"
    case video = "Video"

    var systemImage: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .arScan: return "cube.transparent"
        }
    }
}
