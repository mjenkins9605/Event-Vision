import SwiftUI
import simd

struct ARPlaceView: View {
    var initialProps: [PlacedProp] = []

    @EnvironmentObject var assetStore: AssetStore
    @EnvironmentObject var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var placedProps: [PlacedProp] = []
    @State private var selectedPropID: UUID?
    @State private var selectedAsset: ImageAsset?
    @State private var presetWidth: Float?
    @State private var presetHeight: Float?
    @State private var showAssetPicker = false
    @State private var showSaveAlert = false
    @State private var showDimensions = false
    @State private var scanName = ""
    @State private var trackingStatus = "Initializing..."
    @State private var savedConfirmation: String?

    // Editing dimensions for selected prop
    @State private var editingWidth: Float = 0.5
    @State private var editingHeight: Float = 0.5
    @State private var editingDepth: Float = 0

    private var selectedProp: PlacedProp? {
        guard let id = selectedPropID else { return nil }
        return placedProps.first { $0.id == id }
    }

    private var sizeIsNewPreset: Bool {
        guard let prop = selectedProp else { return false }
        let existing = assetStore.presets(for: prop.assetID)
        let asset = assetStore.assets.first { $0.id == prop.assetID }
        let defaultW: Float = 0.5
        let defaultH: Float = (asset != nil) ? defaultW / asset!.aspectRatio : 0.5
        let matchesDefault = abs(prop.widthMeters - defaultW) < 0.01 && abs(prop.heightMeters - defaultH) < 0.01
        if matchesDefault { return false }
        return !existing.contains { abs($0.widthMeters - prop.widthMeters) < 0.01 && abs($0.heightMeters - prop.heightMeters) < 0.01 }
    }

    var body: some View {
        ZStack {
            // AR scene (full screen)
            ARPlaceSceneView(
                assetStore: assetStore,
                placedProps: $placedProps,
                selectedPropID: $selectedPropID,
                trackingStatus: $trackingStatus,
                selectedAsset: selectedAsset,
                presetWidth: presetWidth,
                presetHeight: presetHeight
            )
            .ignoresSafeArea()

            // Crosshair
            if selectedAsset != nil {
                CrosshairView()
            }

            VStack {
                // Top status bar
                if selectedAsset != nil {
                    HStack(spacing: 10) {
                        Text(trackingStatus)
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
                    Text(trackingStatus)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.top, 8)
                }

                Spacer()

                // Prop editing row (only when a prop is selected)
                if selectedPropID != nil {
                    HStack(spacing: 8) {
                        arPillButton("Size", icon: "ruler", color: Color.white.opacity(0.2)) {
                            showDimensions = true
                        }
                        arPillButton("Copy", icon: "plus.square.on.square", color: Color.orange.opacity(0.8)) {
                            duplicateSelectedProp()
                        }
                        arPillButton("Delete", icon: "trash", color: Color.red.opacity(0.8)) {
                            if let id = selectedPropID {
                                placedProps.removeAll { $0.id == id }
                                selectedPropID = nil
                            }
                        }
                        if sizeIsNewPreset {
                            arPillButton("Preset", icon: "bookmark", color: Color.purple.opacity(0.8)) {
                                let asset = assetStore.assets.first { $0.id == selectedProp?.assetID }
                                presetName = "\(asset?.name ?? "Asset") (Custom)"
                                showSavePresetAlert = true
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Main actions row
                HStack(spacing: 8) {
                    arPillButton("Asset", icon: "photo.on.rectangle", color: .blue) {
                        showAssetPicker = true
                    }
                    if !placedProps.isEmpty {
                        arPillButton("Save Layout", icon: "square.and.arrow.down", color: .green) {
                            scanName = ""
                            showSaveAlert = true
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Spacer().frame(height: 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            placedProps = initialProps
        }
        .onChange(of: selectedPropID) { _, newID in
            if let prop = placedProps.first(where: { $0.id == newID }) {
                editingWidth = prop.widthMeters
                editingHeight = prop.heightMeters
                editingDepth = prop.depthMeters

                // Auto-open size sheet if the asset has no physical dimensions set
                let asset = assetStore.assets.first { $0.id == prop.assetID }
                if asset?.physicalWidthMeters == nil && presetWidth == nil {
                    showDimensions = true
                }
            }
        }
        .onChange(of: editingWidth) { _, newVal in
            guard let id = selectedPropID,
                  let idx = placedProps.firstIndex(where: { $0.id == id }) else { return }
            placedProps[idx].widthMeters = newVal
        }
        .onChange(of: editingHeight) { _, newVal in
            guard let id = selectedPropID,
                  let idx = placedProps.firstIndex(where: { $0.id == id }) else { return }
            placedProps[idx].heightMeters = newVal
        }
        .onChange(of: editingDepth) { _, newVal in
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
        .sheet(isPresented: $showDimensions) {
            NavigationView {
                Form {
                    Section("Dimensions") {
                        DimensionSlider(label: "W", meters: $editingWidth, range: 0.05...5.0)
                        DimensionSlider(label: "H", meters: $editingHeight, range: 0.05...5.0)
                        DimensionSlider(label: "D", meters: $editingDepth, range: 0...5.0, tint: .orange, allowZero: true)
                    }
                }
                .navigationTitle("Edit Size")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDimensions = false }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
        .alert("Save AR Layout", isPresented: $showSaveAlert) {
            TextField("e.g. Lobby Setup", text: $scanName)
            Button("Save") {
                let trimmed = scanName.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? "Untitled Layout" : trimmed
                let scan = SavedScan(name: name, placedProps: placedProps)
                scanStore.save(scan)
                savedConfirmation = "\u{201C}\(name)\u{201D} saved"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    savedConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this layout a name so you can find it later.")
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
        .overlay {
            if let msg = savedConfirmation {
                Text(msg)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .animation(.easeInOut, value: savedConfirmation)
            }
        }
    }

    // Missing state for preset alert
    @State private var showSavePresetAlert = false
    @State private var presetName = ""

    private func duplicateSelectedProp() {
        guard let id = selectedPropID,
              let original = placedProps.first(where: { $0.id == id }) else { return }

        var t = original.transform.matrix
        let right = simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let offset = right * (original.widthMeters * 0.6)
        t.columns.3 += simd_float4(offset, 0)

        let dup = PlacedProp(
            assetID: original.assetID,
            transform: CodableMatrix4x4(t),
            widthMeters: original.widthMeters,
            heightMeters: original.heightMeters,
            depthMeters: original.depthMeters,
            surfaceID: original.surfaceID
        )

        placedProps.append(dup)
        selectedPropID = dup.id
    }

    private func arPillButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption).fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(color)
                .foregroundColor(.white)
                .cornerRadius(20)
        }
    }
}
