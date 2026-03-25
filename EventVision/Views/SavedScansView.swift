import SwiftUI
import simd

// MARK: - Prop Placement View

struct PropPlacementView: View {
    let scan: SavedScan
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var assetStore: AssetStore
    @State private var placedProps: [PlacedProp] = []
    @State private var selectedPropID: UUID?
    @State private var selectedAsset: ImageAsset?
    @State private var showAssetPicker = false
    @State private var isPlacementMode = true
    @State private var editingWidth: Float = 0.5
    @State private var editingHeight: Float = 0.5
    @State private var editingDepth: Float = 0
    @State private var presetWidth: Float?
    @State private var presetHeight: Float?
    @State private var showSavePresetAlert = false
    @State private var presetName = ""

    private var selectedProp: PlacedProp? {
        guard let id = selectedPropID else { return nil }
        return placedProps.first { $0.id == id }
    }

    private var sizeIsNewPreset: Bool {
        guard let prop = selectedProp else { return false }
        let existing = assetStore.presets(for: prop.assetID)
        let asset = assetStore.assets.first { $0.id == prop.assetID }
        // Check against default size
        let defaultW: Float = 0.5
        let defaultH: Float = (asset != nil) ? defaultW / asset!.aspectRatio : 0.5
        let matchesDefault = abs(prop.widthMeters - defaultW) < 0.01 && abs(prop.heightMeters - defaultH) < 0.01
        if matchesDefault { return false }
        return !existing.contains { abs($0.widthMeters - prop.widthMeters) < 0.01 && abs($0.heightMeters - prop.heightMeters) < 0.01 }
    }

    var body: some View {
        ZStack {
            InteractiveRoom3DViewer(
                scan: scan,
                assetStore: assetStore,
                placedProps: $placedProps,
                selectedPropID: $selectedPropID,
                selectedAsset: selectedAsset,
                isPlacementMode: isPlacementMode,
                presetWidth: presetWidth,
                presetHeight: presetHeight
            )
            .ignoresSafeArea(edges: .bottom)

            VStack {
                // Status bar
                if selectedAsset != nil {
                    HStack(spacing: 10) {
                        Text("Tap a surface to place \u{201C}\(selectedAsset!.name)\u{201D}")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Button {
                            selectedAsset = nil
                            presetWidth = nil
                            presetHeight = nil
                        } label: {
                            Text("Done")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.top, 8)
                } else {
                    Text("Choose an asset to start placing")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.top, 8)
                }

                Spacer()

                // Size sliders (visible when a prop is selected)
                if selectedPropID != nil {
                    VStack(spacing: 8) {
                        DimensionSlider(label: "W:", meters: $editingWidth, range: 0.05...5.0, compact: true)
                        DimensionSlider(label: "H:", meters: $editingHeight, range: 0.05...5.0, compact: true)
                        DimensionSlider(label: "D:", meters: $editingDepth, range: 0...5.0, tint: .orange, allowZero: true, compact: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                // Bottom controls
                HStack(spacing: 12) {
                    Button {
                        showAssetPicker = true
                    } label: {
                        Label("Choose Asset", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                    }

                    if selectedPropID != nil {
                        Button {
                            duplicateSelectedProp()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }

                        Button {
                            if let id = selectedPropID {
                                placedProps.removeAll { $0.id == id }
                                selectedPropID = nil
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }
                    }
                }
                .padding(.bottom, 4)

                // Save preset button
                if sizeIsNewPreset {
                    Button {
                        let asset = assetStore.assets.first { $0.id == selectedProp?.assetID }
                        presetName = "\(asset?.name ?? "Asset") (Custom)"
                        showSavePresetAlert = true
                    } label: {
                        Label("Save as Preset", systemImage: "square.and.arrow.down")
                            .font(.subheadline).fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(25)
                    }
                }

                Spacer().frame(height: 16)
            }
        }
        .navigationTitle("Place Props")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            placedProps = scan.placedProps
        }
        .onDisappear {
            // Auto-save props when leaving
            var updated = scan
            updated.placedProps = placedProps
            scanStore.save(updated)
        }
        .onChange(of: selectedPropID) { newID in
            if let prop = placedProps.first(where: { $0.id == newID }) {
                editingWidth = prop.widthMeters
                editingHeight = prop.heightMeters
                editingDepth = prop.depthMeters
            }
        }
        .onChange(of: editingWidth) { newVal in
            guard let id = selectedPropID,
                  let idx = placedProps.firstIndex(where: { $0.id == id }) else { return }
            placedProps[idx].widthMeters = newVal
        }
        .onChange(of: editingHeight) { newVal in
            guard let id = selectedPropID,
                  let idx = placedProps.firstIndex(where: { $0.id == id }) else { return }
            placedProps[idx].heightMeters = newVal
        }
        .onChange(of: editingDepth) { newVal in
            guard let id = selectedPropID,
                  let idx = placedProps.firstIndex(where: { $0.id == id }) else { return }
            placedProps[idx].depthMeters = newVal
        }
        .sheet(isPresented: $showAssetPicker) {
            AssetPickerSheet(
                selectedAsset: $selectedAsset,
                presetWidth: $presetWidth,
                presetHeight: $presetHeight
            )
        }
        .alert("Save as Preset", isPresented: $showSavePresetAlert) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                if let prop = selectedProp {
                    let preset = AssetPreset(
                        assetID: prop.assetID,
                        name: presetName,
                        widthMeters: prop.widthMeters,
                        heightMeters: prop.heightMeters
                    )
                    assetStore.addPreset(preset)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This size will be available as a quick-pick option when placing this asset.")
        }
    }

    private func duplicateSelectedProp() {
        guard let id = selectedPropID,
              let original = placedProps.first(where: { $0.id == id }) else { return }

        // Offset along the surface's local X (right) axis so they don't overlap
        var t = original.transform.matrix
        let right = simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let offset = right * (original.widthMeters * 0.6)
        t.columns.3 += simd_float4(offset, 0)

        let offsetDup = PlacedProp(
            assetID: original.assetID,
            transform: CodableMatrix4x4(t),
            widthMeters: original.widthMeters,
            heightMeters: original.heightMeters,
            depthMeters: original.depthMeters,
            surfaceID: original.surfaceID
        )

        placedProps.append(offsetDup)
        selectedPropID = offsetDup.id
    }
}

// MARK: - Saved Scans List

struct SavedScansView: View {
    @EnvironmentObject var scanStore: ScanStore

    var body: some View {
        Group {
            if scanStore.scans.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Saved Scans")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Complete a room scan and tap Save to store it here.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                List {
                    ForEach(scanStore.scans) { scan in
                        NavigationLink {
                            SavedScanDetailView(scan: scan)
                                .environmentObject(scanStore)
                        } label: {
                            ScanRowView(scan: scan)
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Saved Scans")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Scan Row

struct ScanRowView: View {
    let scan: SavedScan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scan.name)
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 16) {
                Label("\(scan.walls.count) walls", systemImage: "rectangle.portrait")
                    .font(.caption)
                    .foregroundColor(.blue)

                if !scan.doors.isEmpty {
                    Label("\(scan.doors.count) doors", systemImage: "door.left.hand.open")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if !scan.windows.isEmpty {
                    Label("\(scan.windows.count) windows", systemImage: "window.vertical.open")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Text(scan.date, style: .date)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scan Detail View

struct SavedScanDetailView: View {
    let scan: SavedScan
    @EnvironmentObject var scanStore: ScanStore
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirm = false
    @State private var show3D = true
    @State private var showRoomPlan = false

    var body: some View {
        ZStack {
            if show3D {
                if showRoomPlan, let usdzURL = scanStore.usdzURL(for: scan) {
                    USDZRoomViewer(fileURL: usdzURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Room3DViewer(scan: scan)
                        .ignoresSafeArea(edges: .bottom)
                }
            }

            VStack {
                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        NavigationLink {
                            PropPlacementView(scan: scan)
                        } label: {
                            Label("Place Props", systemImage: "square.on.square.badge.person.crop")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }

                        NavigationLink {
                            ARPlaceView(initialProps: scan.placedProps)
                        } label: {
                            Label("AR View", systemImage: "arkit")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        if scanStore.usdzURL(for: scan) != nil {
                            Button {
                                showRoomPlan.toggle()
                            } label: {
                                Label(showRoomPlan ? "3D Measured" : "RoomPlan View",
                                      systemImage: showRoomPlan ? "ruler" : "cube")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(25)
                            }
                        }

                        Button {
                            show3D.toggle()
                        } label: {
                            Label("List", systemImage: "list.bullet")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(get: { !show3D }, set: { if $0 { show3D = false } else { show3D = true } })) {
            SavedScanMeasurementsSheet(scan: scan)
        }
        .alert("Delete Scan", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                scanStore.delete(scan)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \u{201C}\(scan.name)\u{201D}? This cannot be undone.")
        }
    }
}

// MARK: - Measurements Sheet for Saved Scan

struct SavedScanMeasurementsSheet: View {
    let scan: SavedScan
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        SummaryItem(count: scan.walls.count, label: "Walls", icon: "rectangle.portrait")
                        Spacer()
                        SummaryItem(count: scan.doors.count, label: "Doors", icon: "door.left.hand.open")
                        Spacer()
                        SummaryItem(count: scan.windows.count, label: "Windows", icon: "window.vertical.open")
                        Spacer()
                        SummaryItem(count: scan.openings.count, label: "Openings", icon: "rectangle.portrait.arrowtriangle.2.outward")
                    }
                    .padding(.vertical, 8)
                }

                if !scan.walls.isEmpty {
                    Section("Walls") {
                        ForEach(Array(scan.walls.enumerated()), id: \.element.id) { i, wall in
                            SurfaceRow(label: "Wall \(i + 1)", icon: "rectangle.portrait", width: wall.dimensionsX, height: wall.dimensionsY, color: .blue)
                        }
                    }
                }

                if !scan.doors.isEmpty {
                    Section("Doors") {
                        ForEach(Array(scan.doors.enumerated()), id: \.element.id) { i, door in
                            SurfaceRow(label: "Door \(i + 1)", icon: "door.left.hand.open", width: door.dimensionsX, height: door.dimensionsY, color: .green)
                        }
                    }
                }

                if !scan.windows.isEmpty {
                    Section("Windows") {
                        ForEach(Array(scan.windows.enumerated()), id: \.element.id) { i, window in
                            SurfaceRow(label: "Window \(i + 1)", icon: "window.vertical.open", width: window.dimensionsX, height: window.dimensionsY, color: .orange)
                        }
                    }
                }

                if !scan.openings.isEmpty {
                    Section("Openings") {
                        ForEach(Array(scan.openings.enumerated()), id: \.element.id) { i, opening in
                            SurfaceRow(label: "Opening \(i + 1)", icon: "rectangle.portrait.arrowtriangle.2.outward", width: opening.dimensionsX, height: opening.dimensionsY, color: .purple)
                        }
                    }
                }
            }
            .navigationTitle(scan.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
