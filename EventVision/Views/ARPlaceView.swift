import SwiftUI
import UIKit
import simd

struct ARPlaceView: View {
    var initialProps: [PlacedProp] = []
    var existingScanID: UUID?

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
    @State private var showSavePresetAlert = false
    @State private var presetName = ""
    @State private var snapshotTrigger = 0
    @State private var interactionMode: PropInteractionHelper.InteractionMode = .move
    @State private var showFlash = false

    private var canUpdateExistingScan: Bool {
        guard let id = existingScanID else { return false }
        return scanStore.scans.contains { $0.id == id }
    }

    private var selectedProp: PlacedProp? {
        guard let id = selectedPropID else { return nil }
        return placedProps.first { $0.id == id }
    }

    private var sizeIsNewPreset: Bool {
        selectedProp?.isNewPresetSize(assetStore: assetStore) ?? false
    }

    var body: some View {
        ZStack {
            // AR scene (full screen)
            ARPlaceSceneView(
                assetStore: assetStore,
                placedProps: $placedProps,
                selectedPropID: $selectedPropID,
                trackingStatus: $trackingStatus,
                snapshotTrigger: snapshotTrigger,
                onSnapshot: { image in
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    showFlash = true
                    savedConfirmation = "Saved to Camera Roll"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showFlash = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedConfirmation = nil
                    }
                },
                selectedAsset: selectedAsset,
                presetWidth: presetWidth,
                presetHeight: presetHeight,
                interactionMode: interactionMode
            )
            .ignoresSafeArea()

            // Camera flash
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: showFlash)
            }

            // Crosshair
            if selectedAsset != nil {
                CrosshairView()
            }

            // Move/Rotate toggle — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        interactionMode = (interactionMode == .move) ? .rotate : .move
                    } label: {
                        Image(systemName: interactionMode == .move
                              ? "arrow.triangle.2.circlepath"
                              : "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
                Spacer()
            }

            VStack {
                // Top status bar
                if selectedAsset != nil {
                    HStack(spacing: 10) {
                        Text(trackingStatus)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

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
                        arPillButton("Photo", icon: "camera.fill", color: Color.white.opacity(0.3)) {
                            snapshotTrigger += 1
                        }
                        arPillButton("Save", icon: "square.and.arrow.down", color: .green) {
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
            if !canUpdateExistingScan {
                TextField("e.g. Lobby Setup", text: $scanName)
            }
            Button("Save") {
                if canUpdateExistingScan,
                   let existingID = existingScanID,
                   let idx = scanStore.scans.firstIndex(where: { $0.id == existingID }) {
                    var updated = scanStore.scans[idx]
                    updated.placedProps = placedProps
                    scanStore.save(updated)
                    savedConfirmation = "\u{201C}\(updated.name)\u{201D} updated"
                } else {
                    let trimmed = scanName.trimmingCharacters(in: .whitespaces)
                    let name = trimmed.isEmpty ? "Untitled Layout" : trimmed
                    let scan = SavedScan(name: name, placedProps: placedProps)
                    scanStore.save(scan)
                    savedConfirmation = "\u{201C}\(name)\u{201D} saved"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    savedConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canUpdateExistingScan {
                Text("Update the placed props on this scan?")
            } else {
                Text("Give this layout a name so you can find it later.")
            }
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


    private func duplicateSelectedProp() {
        guard let id = selectedPropID,
              let original = placedProps.first(where: { $0.id == id }) else { return }
        let dup = original.duplicated()
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

