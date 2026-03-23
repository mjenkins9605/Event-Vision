import SwiftUI

struct HomeView: View {
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var assetStore: AssetStore

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color(white: 0.08), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Marquee title with twinkling lights
                    VStack(spacing: 20) {
                        MarqueeText("EVENT")
                        MarqueeText("VISION")
                    }
                    .padding(.bottom, 12)

                    Text("Event &amp; Premiere Planning")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                        .tracking(3)
                        .textCase(.uppercase)

                    Spacer()

                    // New Capture card
                    NavigationLink {
                        CaptureFlowView()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("New Capture")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Photo, video, or room scan")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)

                    // Saved Scans card
                    NavigationLink {
                        SavedScansView()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "archivebox.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Saved Scans")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(scanStore.scans.isEmpty
                                     ? "No scans yet"
                                     : "\(scanStore.scans.count) scan\(scanStore.scans.count == 1 ? "" : "s") saved")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Asset Library card
                    NavigationLink {
                        AssetLibraryView()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Asset Library")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(assetStore.assets.isEmpty
                                     ? "Import event images"
                                     : "\(assetStore.assets.count) asset\(assetStore.assets.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Spacer()
                        .frame(height: 80)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Marquee Text with Twinkling Bulbs

struct MarqueeText: View {
    let text: String
    private let fontSize: CGFloat = 52
    private let tracking: CGFloat = 18
    private let bulbSpacing: CGFloat = 14
    private let bulbSize: CGFloat = 4
    private let padding: CGFloat = 14

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .black, design: .default))
            .tracking(tracking)
            .foregroundColor(.white)
            .padding(.horizontal, padding)
            .padding(.vertical, padding * 0.6)
            .overlay {
                GeometryReader { geo in
                    MarqueeBulbs(
                        size: geo.size,
                        spacing: bulbSpacing,
                        bulbSize: bulbSize
                    )
                }
            }
    }
}

struct MarqueeBulbs: View {
    let size: CGSize
    let spacing: CGFloat
    let bulbSize: CGFloat

    @State private var animating = false

    private var bulbPositions: [CGPoint] {
        var points: [CGPoint] = []
        let w = size.width
        let h = size.height

        // Top edge (left to right)
        var x: CGFloat = 0
        while x <= w {
            points.append(CGPoint(x: x, y: 0))
            x += spacing
        }
        // Right edge (top to bottom, skip corners)
        var y: CGFloat = spacing
        while y <= h - spacing {
            points.append(CGPoint(x: w, y: y))
            y += spacing
        }
        // Bottom edge (right to left)
        x = w
        while x >= 0 {
            points.append(CGPoint(x: x, y: h))
            x -= spacing
        }
        // Left edge (bottom to top, skip corners)
        y = h - spacing
        while y >= spacing {
            points.append(CGPoint(x: 0, y: y))
            y -= spacing
        }

        return points
    }

    var body: some View {
        let positions = bulbPositions
        let total = positions.count

        Canvas { context, canvasSize in
            // Canvas is just used for layout — actual bulbs are in the overlay
        }
        .overlay {
            ForEach(Array(positions.enumerated()), id: \.offset) { index, point in
                BulbDot(
                    bulbSize: bulbSize,
                    index: index,
                    total: total,
                    animating: animating
                )
                .position(point)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

struct BulbDot: View {
    let bulbSize: CGFloat
    let index: Int
    let total: Int
    let animating: Bool

    // Each bulb gets a phase offset so they twinkle in a wave pattern
    private var phase: Double {
        Double(index) / Double(max(total, 1))
    }

    // Warm white / soft gold color
    private var bulbColor: Color {
        Color(red: 1.0, green: 0.95, blue: 0.75)
    }

    var body: some View {
        let baseOpacity = animating
            ? 0.3 + 0.7 * sin2(phase)
            : 0.5

        Circle()
            .fill(bulbColor)
            .frame(width: bulbSize, height: bulbSize)
            .shadow(color: bulbColor.opacity(baseOpacity * 0.8), radius: 4, x: 0, y: 0)
            .opacity(baseOpacity)
            .animation(
                .easeInOut(duration: Double.random(in: 1.2...2.2))
                .repeatForever(autoreverses: true)
                .delay(phase * 1.5),
                value: animating
            )
    }

    // Attempt a wave pattern using simple math
    private func sin2(_ p: Double) -> Double {
        return (sin(p * .pi * 2) + 1) / 2
    }
}

#Preview {
    HomeView()
        .environmentObject(ScanStore())
        .environmentObject(AssetStore())
}
