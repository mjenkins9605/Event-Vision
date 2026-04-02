# Event Vision - Project Summary

**Last updated:** April 1, 2026 (Session 6)
**Platform:** iOS (Swift / SwiftUI)
**Xcode:** 26.3
**Tested on:** iPhone 16 (no LiDAR), iPhone 14 Pro Max (LiDAR)

---

## What is Event Vision?

An iOS app for planning events and premieres remotely. The core idea: go to a venue, scan the room with your phone, get accurate dimensions of walls/doors/windows/openings, take photos and videos for reference, and place event assets (banners, signage, decor) into the scanned space via AR. This lets you plan events from across the country without being physically present at the venue again.

**Future platforms:** Web companion (limited features), Android (later phase).

---

## Architecture Decision

We chose **Option A: Native iOS** over React Native or Flutter because:
- Apple&rsquo;s RoomPlan API (LiDAR) does automatic room scanning with dimensions out of the box
- ARKit gives the best AR experience on iOS
- Cross-platform frameworks have weak AR support

**Tech stack:** Swift, SwiftUI, ARKit, RoomPlan, SceneKit, AVFoundation

---

## Current Project Structure

```
Event-Vision/
  EventVision.xcodeproj/
  EventVision/
    EventVisionApp.swift              - App entry point, injects ScanStore + AssetStore
    ContentView.swift                 - CaptureFlowView (camera/AR flow, pushed from home)
    Info.plist                        - Camera, microphone, photo library permissions
    Models/
      CaptureMode.swift               - Enum: .arScan, .photo, .video, .arPlace
      MeasurementFormatter.swift      - Shared feet/inches formatting + conversion helpers + Float.clamped
      SavedScan.swift                 - Codable model for persisted scans + CodableMatrix4x4
      ScanStore.swift                 - Async JSON + USDZ persistence with pending mutation queue
      ImageAsset.swift                - ImageAsset, PlacedProp, VendorQuote, AssetPreset + shared helpers
      AssetStore.swift                - Image library + preset persistence + NSCache image cache (50MB)
      PropNodeBuilder.swift           - SCNNode creation, PBR lighting, shadows, labels, rotation gizmo
      PropInteractionHelper.swift     - Shared prop interaction logic (sync, selection, rotation, transforms)
    Views/
      HomeView.swift                  - Home page with marquee title + navigation cards
      ModeSelectorView.swift          - Bottom tab bar for switching between AR Scan/Photo/Video/AR Place
      CameraView.swift                - Camera preview + photo capture + video recording + save
      ManualMeasureView.swift         - ARKit manual measurement for non-LiDAR devices
      RoomScanView.swift              - LiDAR scanning + 3D viewer + USDZ viewer + save scan flow
      SavedScansView.swift            - Saved scans list, detail, prop placement + move/rotate + AR View
      AssetLibraryView.swift          - Image asset library (import, grid, tap to detail)
      AssetPickerSheet.swift          - Compact asset picker with presets + info button
      AssetDetailView.swift           - Asset detail/edit: vendor info, quotes, W x H x D dimensions
      DimensionSlider.swift           - Reusable slider + manual feet/inches input component
      InteractiveRoom3DViewer.swift   - Placement-enabled 3D viewer (delegates to PropInteractionHelper)
      ARPlaceView.swift               - Live AR placement SwiftUI host (controls, save, screenshot/share)
      ARPlaceSceneView.swift          - Live AR placement UIViewRepresentable + Coordinator
    Assets.xcassets/
    Preview Content/
```

---

## App Flow

### Home Page (`HomeView`)
- Marquee-style "EVENT VISION" title with twinkling light bulbs around each word
- "Event & Premiere Planning" subtitle
- Three navigation cards:
  - **New Capture** &mdash; pushes to `CaptureFlowView` (AR Scan/Photo/Video/AR Place)
  - **Saved Scans** &mdash; pushes to `SavedScansView` (list of persisted scans)
  - **Asset Library** &mdash; pushes to `AssetLibraryView` (event image management)
- Camera does NOT open on app launch &mdash; user must tap into it

### Capture Flow (`CaptureFlowView`, formerly `ContentView`)
- Default mode is **AR Scan** (not photo)
- Mode selector at bottom: AR Scan | Photo | Video | AR Place
- Custom back button ("Home") stops camera session before dismissing
- Camera session and AR session handoff managed via completion handler
- Both `.arScan` and `.arPlace` modes tear down the camera session before starting AR

### LiDAR Scan Flow (`LiDARScanView`)
1. User taps "Start Scan"
2. RoomPlan scanning UI appears (built-in coaching, real-time room detection)
3. User walks around the room, taps "Done"
4. Auto-switches to custom 3D measured viewer
5. Post-scan buttons in a **2&times;2 grid layout**:
   - Row 1: "3D Measured" / "RoomPlan View" toggle | "List" (surface sheet)
   - Row 2: "Save" (name prompt) | "Rescan"

### Live AR Prop Placement (`ARPlaceView` + `ARPlaceSceneView`)
**Two entry points:**
1. **New Capture &rarr; AR Place tab** &mdash; 4th mode in the bottom tab bar
2. **Saved Scans &rarr; tap a scan &rarr; AR View** &mdash; loads existing placed props into the AR scene and saves back to the same scan

**Flow:**
1. **ARCoachingOverlayView** appears automatically with hand+phone animation until tracking is ready
2. **Dot grid planes** appear on detected surfaces (tiling cyan dots every 20cm)
3. Select an asset via "Asset" button &rarr; asset picker sheet
4. **Ghost preview** (translucent prop with breathing pulse animation) follows screen center via per-frame ARKit raycasts
5. Tap a detected surface to place the prop &mdash; **haptic feedback** fires on placement
6. **Placement bounce animation** (scale 0.01 &rarr; 1.08 &rarr; 1.0 over 0.32s)
7. **Soft radial shadow** appears beneath every placed prop for ground contact
8. On **horizontal surfaces** (floor/table): prop stands upright facing the camera
9. On **vertical surfaces** (walls): prop places flush against the wall
10. If the asset has no physical dimensions set, the **Size sheet auto-opens** after placement
11. Tap an existing prop to select it (**haptic**) &rarr; 3-axis rotation rings appear
12. **Pinch to scale** &mdash; two-finger pinch resizes the selected prop proportionally (0.05&ndash;5.0m)
13. **Photo** button captures AR scene screenshot and opens share sheet
14. **Save Layout** button &rarr; name prompt (or update confirmation for existing scans)

**Compact controls (two rows):**
- Top row (when prop selected): Size | Copy | Delete | Preset
- Bottom row: Asset | Photo | Save Layout
- All buttons use `.caption` font with `.lineLimit(1)` and `.fixedSize()` to prevent text wrapping
- Size opens a half-sheet with W/H/D `DimensionSlider` components

**AR Scene Coordinator (`ARPlaceSceneView.Coordinator`):**
- Conforms to `ARSCNViewDelegate`, `ARSessionDelegate`, `UIGestureRecognizerDelegate`
- **ARCoachingOverlayView** wired up with `.anyPlane` goal, activates automatically
- **Ghost preview:** Per-frame raycast from screen center, breathing opacity pulse (0.3&ndash;0.6), rebuilds on asset or preset dimension change
- **Tap to place:** ARKit raycast &rarr; `PropNodeBuilder.surfaceAlignedTransform` (or `uprightTransform` for horizontal surfaces) &rarr; `PlacedProp` &rarr; `PropNodeBuilder.makeNode` &rarr; medium haptic
- **Pinch to scale:** `UIPinchGestureRecognizer` with simultaneous recognition alongside pan
- **Select / Move / Rotate:** Delegated to `PropInteractionHelper`
- **Haptics:** Light on selection/ring tap, medium on placement, notification on first plane detected
- **Session interruption:** `sessionWasInterrupted`/`sessionInterruptionEnded` delegates re-run config with `.resetTracking`
- **Snapshot:** `snapshotTrigger` int counter &rarr; `ARSCNView.snapshot()` &rarr; `UIActivityViewController` share sheet
- AR session runs continuously during gestures (no pause/resume)
- `suppressTransformSync` flag prevents stale binding data from snapping props back after gesture ends

### Scan Persistence
- **Save:** After scan, tap green "Save" button &rarr; alert prompts for name &rarr; saved as JSON in `Documents/EventVision/Scans/{uuid}.json` **+ USDZ export** at `{uuid}.usdz`
- **AR-only saves:** `SavedScan(name:placedProps:)` creates a scan with empty surface arrays and just placed props (no room geometry, no USDZ)
- **AR View from saved scans:** When opened via "AR View" on a saved scan, saving updates the **existing scan** (not a new orphan) via `existingScanID`
- **USDZ export:** `CapturedRoom.export(to:)` is called automatically on every LiDAR scan save
- **View:** Home &rarr; Saved Scans &rarr; tap scan &rarr; 3D viewer with measurements
- **Delete:** Two-step: tap "Delete" &rarr; confirmation alert &mdash; deletes both JSON and USDZ files
- **Data stored:** All surface dimensions + full `simd_float4x4` transforms for walls, doors, windows, openings, placed props, and USDZ 3D model

### Saved Scan Detail View (`SavedScanDetailView`)
- **RoomPlan View / 3D Measured toggle** &mdash; switches between USDZ model (with furniture, rotate/zoom) and measured view with dimension labels. Only appears if `.usdz` file exists for the scan.
- **List** button &mdash; opens measurements sheet (dedicated `showMeasurements` state)
- **Place Props** &mdash; navigates to offline 3D prop placement
- **AR View** &mdash; navigates to live AR placement with scan&rsquo;s props pre-loaded + `existingScanID`
- **Delete** &mdash; with confirmation

### Prop Placement (Offline 3D)
1. Home &rarr; Saved Scans &rarr; tap a scan &rarr; tap "Place Props"
2. Tap "Choose Asset" &rarr; asset picker sheet &rarr; select an image (or preset)
3. Tap any wall/surface in the 3D viewer &rarr; prop appears flush against it, **always facing the camera** (normal auto-flipped if needed)
4. Tap "Done" in the status bar to **stop placement mode**
5. Tap "Choose Asset" again to re-enter placement mode and add more
6. Tap an existing prop &rarr; yellow highlight + **3-axis rotation rings** appear &rarr; controls:
   - **Tap a ring** &mdash; rotates 45&deg; on that axis
   - **Drag along a ring** &mdash; continuous rotation with correct screen-space direction
   - **Red ring** (X-axis) &mdash; pitch rotation
   - **Green ring** (Y-axis) &mdash; yaw/turntable rotation
   - **Blue ring** (Z-axis) &mdash; roll/spin on wall
   - **Drag the prop body** (one finger) &mdash; moves it in 3D space
   - **W/H/D sliders** with manual feet/inches input (tap the label to type exact values)
   - **Duplicate** button &mdash; copies the prop offset to the right (via `PlacedProp.duplicated()`)
   - **Remove** button &mdash; deletes the selected prop
   - **Save as Preset** button &mdash; appears when size differs from known presets (via `PlacedProp.isNewPresetSize(assetStore:)`)
7. Props with depth > 0 render as **3D boxes** (image on front face, gray sides) with a **red floor footprint** showing ground coverage and a depth label
8. Navigate back &rarr; props auto-saved to the scan&rsquo;s JSON

### Asset Library
- Grid of imported images with names and dimension badges (W &times; H &times; D)
- Import via PhotosPicker (tap + in nav bar) &rarr; name prompt
- **Tap any asset** &rarr; navigates to `AssetDetailView` for editing
- Delete via context menu (long-press) or from detail view
- Images stored as JPEGs in `Documents/EventVision/Assets/{uuid}.jpg`
- JSON manifests at `Documents/EventVision/Assets/assets.json` and `presets.json`

### Asset Detail View (`AssetDetailView`)
- Image preview at top
- **Name** &mdash; editable text field
- **Physical Dimensions (W &times; H &times; D)** &mdash; toggle on/off, three `DimensionSlider` components
- **Vendor** section &mdash; Company name, address, phone
- **Quotes** section &mdash; Multiple vendor quotes, each with $ amount, note, and date
- **Notes** &mdash; free-text area
- **Delete** button with confirmation
- Auto-saves all changes on disappear

### Asset Picker (during placement)
- 3-column grid showing all assets + their presets grouped beneath
- Presets show a purple size badge (W &times; H)
- **Info button (&oplus;)** on each item opens `AssetDetailView` as a sheet
- Tapping an item quick-selects and dismisses
- Tapping a preset selects the asset with preset dimensions pre-applied

---

## Data Models

### ImageAsset
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Auto-generated |
| name | String | User-editable |
| filename | String | e.g. `{uuid}.jpg` |
| dateAdded | Date | For sort order |
| originalWidth/Height | Int | Pixel dimensions of source image |
| vendorName | String? | Company/vendor name |
| vendorAddress | String? | Vendor street address |
| vendorPhone | String? | Vendor phone number |
| notes | String? | Free-text notes |
| quotes | [VendorQuote]? | Array of pricing quotes |
| physicalWidthMeters | Float? | Real-world width |
| physicalHeightMeters | Float? | Real-world height |
| physicalDepthMeters | Float? | Real-world depth (distance from wall) |

### VendorQuote
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Auto-generated |
| amount | String | Flexible format (e.g. "150", "TBD") |
| note | String | Context (e.g. "bulk discount", "rush fee") |
| dateAdded | Date | When the quote was added |

### PlacedProp
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Auto-generated |
| assetID | UUID | FK &rarr; ImageAsset.id |
| transform | CodableMatrix4x4 | 3D position + rotation (updated by move/rotate gestures) |
| widthMeters | Float | Rendered width on wall |
| heightMeters | Float | Rendered height on wall |
| depthMeters | Float | How far it extends from wall (0 = flat) |
| surfaceID | UUID? | Optional FK &rarr; SavedSurface.id |

**Shared helpers (extensions on PlacedProp):**
- `isNewPresetSize(assetStore:)` &mdash; checks if current size differs from defaults and all existing presets
- `duplicated()` &mdash; returns a copy offset to the right along local X axis

### AssetPreset
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Auto-generated |
| assetID | UUID | FK &rarr; ImageAsset.id |
| name | String | e.g. "Banner A (Large)" |
| widthMeters | Float | Preset width |
| heightMeters | Float | Preset height |
| dateCreated | Date | When saved |

### SavedScan
- id, name, date, walls/doors/windows/openings arrays of `SavedSurface`, `placedProps` array
- `SavedSurface`: dimensions (x,y,z) + transform via `CodableMatrix4x4`
- `CodableMatrix4x4`: wraps `simd_float4x4` as `[[Float]]` for JSON serialization
- Backward-compatible decoding: `placedProps` defaults to `[]`, `depthMeters` defaults to `0`
- **`init(name:placedProps:)` initializer** for AR-only placement sessions (empty surface arrays)

---

## What Each File Does

### EventVisionApp.swift
- Creates `ScanStore` and `AssetStore` as `@StateObject`
- Injects both as `.environmentObject()` to the view hierarchy

### ContentView.swift (CaptureFlowView)
- Owns the `CameraManager` as a `@StateObject`
- Switches between `CameraView` (photo/video), `RoomScanView` (AR scan), and `ARPlaceView` (AR place)
- Waits for camera session to fully stop before allowing AR modes (prevents freeze)
- Shows "Starting AR..." spinner during transition
- Default mode: `.arScan`

### HomeView.swift
- `NavigationStack` root view
- Marquee title using `MarqueeText` with `MarqueeBulbs`
- `BulbDot` animation duration derived from index (not random) for stable re-renders
- Three `NavigationLink` cards for New Capture, Saved Scans, Asset Library

### CameraView.swift
- Live camera preview using `AVCaptureVideoPreviewLayer`
- `CameraManager` handles photo capture, video recording, session lifecycle
- `stopSession(completion:)` &mdash; synchronous stop, no sleep delay, completion on main thread

### ManualMeasureView.swift (non-LiDAR devices)
- Uses `ARSCNView` (SceneKit) for AR measurement
- Walk mode (camera position) and Point mode (raycast)
- Multi-point measurement with segment distances + total
- All `points` access safely on main thread (data race fixed)

### RoomScanView.swift (LiDAR devices)
- Auto-detects LiDAR and routes to `LiDARScanView` or `ManualMeasureView`
- `RoomCaptureViewController` wrapper for RoomPlan
- `Room3DViewer` for 3D visualization with measurement labels &mdash; calls `PropNodeBuilder.makeImageLabel` for label rendering (no local duplication)
- `USDZRoomViewer` for loading and displaying exported `.usdz` files
- Post-scan buttons in 2&times;2 grid layout

### ARPlaceView.swift (Live AR Placement &mdash; SwiftUI Host)
- Hosts `ARPlaceSceneView` (the AR rendering layer)
- Manages all SwiftUI state: `placedProps`, `selectedPropID`, `selectedAsset`, `presetWidth/Height`, `showAssetPicker`, `showDimensions`, `showSaveAlert`, `trackingStatus`
- Accepts `initialProps: [PlacedProp]` and optional `existingScanID: UUID?` for editing existing scans
- `canUpdateExistingScan` computed property safely handles deleted scans
- Compact two-row button layout using `arPillButton` helper
- Size sheet (`.presentationDetents([.medium])`) with W/H/D `DimensionSlider` components
- Auto-opens Size sheet when placing an asset without physical dimensions
- **Photo button** &rarr; `snapshotTrigger` &rarr; AR snapshot &rarr; `ShareSheet` (UIActivityViewController)
- Save flow: name prompt for new scans, update confirmation for existing scans
- `ShareSheet` struct wraps `UIActivityViewController` as `UIViewControllerRepresentable`

### ARPlaceSceneView.swift (Live AR Placement &mdash; UIViewRepresentable)
- `UIViewRepresentable` wrapping `ARSCNView`
- AR session: `ARWorldTrackingConfiguration` with horizontal + vertical plane detection, optional `.sceneDepth`, `.automatic` environment texturing
- **ARCoachingOverlayView** with `.anyPlane` goal, auto-activates
- **Dot grid plane visualization** &mdash; tiling cyan dot pattern at 20cm intervals, cached static texture
- **Ghost preview:** Per-frame raycast from screen center, breathing opacity pulse, rebuilds on asset/preset change
- **Tap to place:** ARKit raycast &rarr; orientation choice &rarr; `PlacedProp` &rarr; medium haptic
- **Pinch to scale:** `UIPinchGestureRecognizer` scales selected prop proportionally, clamped 0.05&ndash;5.0m
- **Haptic feedback:** Light (select/ring), medium (place), notification (first plane)
- **Session interruption:** `sessionWasInterrupted`/`sessionInterruptionEnded` with config re-run + `.resetTracking`
- **Snapshot:** `snapshotTrigger` counter &rarr; `uiView.snapshot()` &rarr; `onSnapshot` callback
- **Coordinator** conforms to `ARSCNViewDelegate`, `ARSessionDelegate`, `UIGestureRecognizerDelegate`
- **Gesture handling:** Delegates shared logic to `PropInteractionHelper`
- **Transform sync guards:** `isDragging` and `suppressTransformSync` via helper

### PropInteractionHelper.swift (Shared Interaction Logic &mdash; NEW in Session 6)
- Used by both `ARPlaceSceneView.Coordinator` and `InteractiveRoom3DViewer.Coordinator`
- Owns: `propNodes` dictionary, `selectionHighlight`, `gizmoNode`, all drag state
- **`syncProps(_:rootNode:assetStore:)`** &mdash; diffs propNodes against binding, adds/removes/updates/syncs transforms
- **Placement bounce animation** on new props (scale 0.01 &rarr; 1.08 &rarr; 1.0)
- **`updateSelection(_:)`** &mdash; yellow highlight + 3-axis rotation gizmo
- **`applyRotation45(to:axis:)`** &mdash; 45&deg; snap rotation on ring tap
- **`applyDragRotation(to:axis:currentLocation:scnView:)`** &mdash; continuous screen-drag rotation
- **`screenDragToRotationAngle`** &mdash; 2D cross product of projected axis and drag vector
- **`endDrag()`** &mdash; centralized drag-end (reset flags + restore gizmo visibility)
- **`commitTransform(for:from:updateBinding:)`** &mdash; async write to binding via closure
- **`shouldBeginPan`**, **`detectDragMode`**, **`findTappedProp`**, **`handleRingTap`** &mdash; gesture helpers
- **`findAsset`**, **`isDescendant`** &mdash; utilities

### PropNodeBuilder.swift
- `makeNode(for:image:assetName:)` &mdash; creates either:
  - **Flat plane** (SCNPlane) when depth = 0
  - **3D box** (SCNBox) when depth > 0, with image textured on front face (material index 0), gray sides
- **Physically-based lighting** on prop faces (`lightingModel = .physicallyBased`, `roughness: 0.6`) &mdash; responds to ARKit environment lighting
- **`addShadow(to:prop:)`** &mdash; soft radial gradient shadow plane beneath each prop (cached texture, 60% opacity)
- `addFloorFootprint(to:prop:)` &mdash; semi-transparent red rectangle on floor showing depth coverage + depth label
- `updateNodeSize` &mdash; rebuilds geometry, shadow + label when sliders change
- `makePropLabel` &mdash; floating billboard label showing `"Asset Name &mdash; W &times; H &times; D"`
- `surfaceAlignedTransform` &mdash; orients props flush against walls
- `makeImageLabel` / `renderLabelImage` &mdash; shared label rendering (used by Room3DViewer too)
- **`makeRotationGizmo(faceWidth:faceHeight:)`** &mdash; builds 3 color-coded SCNTorus rings (X=red, Y=green, Z=blue) with fat invisible hit-test tubes and arrow indicators
- **`rotationAxis(for:)`** &mdash; walks up node hierarchy to identify which ring axis was hit
- **Arrow image cache** (`arrowImageCache`) &mdash; renders once per color, reuses
- **Shadow image cache** (`shadowImageCache`) &mdash; renders once, reuses

### MeasurementFormatter.swift
- `feetInches(_ meters:)` &mdash; converts meters to `"7'3""` format
- `toFeetInches(_ meters:)` &mdash; splits meters into (feet, inches) tuple
- `toMeters(feet:inches:)` &mdash; converts feet/inches back to meters
- `Float.clamped(to:)` &mdash; utility extension for range clamping

### ScanStore.swift
- JSON file-based storage: one `.json` file per scan in `Documents/EventVision/Scans/`
- **Async loading:** `loadAllAsync()` reads on background queue, updates main thread
- **Pending mutation queue:** `save()` and `delete()` called before load completes are queued and replayed after load finishes (race condition fix)
- **`isLoaded` flag** prevents background load from overwriting in-flight saves
- **USDZ export:** `save(_:room:)` accepts optional `CapturedRoom` and calls `room.export(to:)`
- `usdzURL(for:)` returns the USDZ file URL if it exists for a given scan
- `delete(_:)` removes both `.json` and `.usdz` files

### AssetStore.swift
- JPEG file storage + `assets.json` manifest + `presets.json` manifest
- **NSCache image cache** (`imageCache`) with 50MB `totalCostLimit`
  - Cost calculated from decoded pixel data (`cgImage.bytesPerRow * cgImage.height`), not compressed JPEG bytes
  - Cache evicted on asset deletion
- Methods: `importImage`, `loadImage` (cache-first), `updateAsset`, `deleteAsset`
- Preset CRUD: `addPreset`, `deletePreset`, `presets(for:)`
- Cascade-deletes presets when parent asset is deleted

### ImageAsset.swift
- `ImageAsset` with vendor info, physical dimensions (W &times; H &times; D), custom encoder/decoder
- `VendorQuote` for tracking pricing quotes
- `PlacedProp` with depth support, backward-compatible decoding, and shared helpers (`isNewPresetSize`, `duplicated`)
- `AssetPreset` for reusable size configurations
- Legacy support: reads old `physicalLengthMeters` key as `physicalWidthMeters`

### InteractiveRoom3DViewer.swift
- `UIViewRepresentable` with `Coordinator` (conforms to `UIGestureRecognizerDelegate`)
- **Delegates to `PropInteractionHelper`** for all shared prop logic (syncProps, updateSelection, rotation, transforms)
- Coordinator owns `helper: PropInteractionHelper` + move-specific drag state (`dragStartScreenZ`, `dragStartWorldPos`)
- `buildRoom(in:)` / `addSurface(to:...)` renders room geometry with colored planes + edge lines + billboarded labels
- Surface nodes tagged as `"surface"` for placement hit testing
- Floor geometry (`SCNFloor`) at lowest wall Y position

### SavedScansView.swift
- `PropPlacementView` &mdash; full placement UI with `InteractiveRoom3DViewer`, dimension sliders, duplicate/delete/preset (all using shared helpers)
- `SavedScansView` &mdash; list of saved scans
- `SavedScanDetailView` &mdash; RoomPlan View / 3D Measured toggle + Place Props + AR View + List + Delete
  - `showMeasurements` state (replaces old inverted `!show3D` binding)
  - AR View passes `existingScanID: scan.id`
- `SavedScanMeasurementsSheet` &mdash; full surface dimensions list
- All `onChange` modifiers use two-argument form (iOS 17+)

### Other Views
- **AssetLibraryView.swift** &mdash; PhotosPicker, grid of NavigationLinks to AssetDetailView
- **AssetPickerSheet.swift** &mdash; Grid of assets + presets, info button, preset selection
- **AssetDetailView.swift** &mdash; Full detail/edit form, auto-saves on disappear
- **DimensionSlider.swift** &mdash; Reusable slider + tappable feet/inches label, compact mode
- **ModeSelectorView.swift** &mdash; Horizontal row of mode buttons

---

## Bugs Fixed (Session 1 &mdash; March 21)

1. **Camera preview not showing:** Fixed with custom `PreviewView` overriding `layerClass`
2. **Crash switching AR to Photo/Video:** Moved `CameraManager` to parent, passed via `@EnvironmentObject`
3. **RoomPlan freeze on Start Scan:** Used `UIViewControllerRepresentable` with real VC as delegate
4. **White screen on iPhone 14 Pro Max:** Dedicated serial `DispatchQueue` for session ops
5. **Camera + AR session conflict:** Stop camera with completion handler before AR starts
6. **Flashlight flickers then dies:** Wait for tracking `.normal` before torch
7. **"7'12"" formatting:** Carry 12" into next foot in `MeasurementFormatter`
8. **"Error: capture view not ready" on Rescan:** Keep RoomPlan view alive (opacity toggle)
9. **Measurement labels not on edges:** UIImage-rendered labels on SCNPlanes with billboard constraints

## Fixes Applied (Session 2 &mdash; March 22)

1. **Video memory spike:** Replaced `Data(contentsOf:)` with `FileManager.copyItem()` in `saveVideo()`
2. **Camera session race condition:** `requestPermissionAndConfigure()` takes a completion handler
3. **Deprecated hitTest API:** Replaced with `raycastQuery` + `session.raycast()`
4. **@MainActor isolation:** Deferred to Swift 6 strict concurrency migration

## Features Added (Session 3 &mdash; March 22)

1. **Prop labels:** Floating billboard labels on every placed prop showing name + dimensions
2. **Duplicate props:** Copy a placed prop offset to the right, preserving all dimensions including depth
3. **Resize props:** W/H/D sliders in placement toolbar with real-time 3D updates
4. **Manual dimension input:** Tap any dimension label to type exact feet/inches values
5. **Asset presets:** Save custom sizes as reusable presets, shown in asset picker grouped under parent asset
6. **Asset detail view:** Full edit screen with vendor info, quotes, and physical dimensions
7. **Physical dimensions drive placement:** Assets with real-world dimensions auto-place at correct size
8. **3D depth rendering:** Props with depth > 0 render as SCNBox + red floor footprint + depth label
9. **Backward-compatible persistence:** All new fields use `decodeIfPresent`

## Features Added (Session 4 &mdash; March 22)

1. **Done button for placement mode**
2. **SCNBox face order fix** (material index 4 &rarr; 0)
3. **RoomPlan View / 3D Measured toggle on saved scans**
4. **USDZ export on save** via `CapturedRoom.export(to:)`
5. **USDZ viewer (`USDZRoomViewer`)**
6. **USDZ cleanup on delete**
7. **Post-scan 2&times;2 button grid**
8. **Prop move (drag)** via `projectPoint`/`unprojectPoint`
9. **Prop rotation handles** (blue Z-axis, orange Y-axis)
10. **Auto-face camera on placement** via `simd_dot` normal check
11. **Room3DViewer `showMeasurements` toggle**

## Features Added (Session 5 &mdash; March 24)

1. **Live AR prop placement** (`ARPlaceView` + `ARPlaceSceneView`) with ghost preview, tap-to-place, select/move/rotate, save-as-scan
2. **4th capture mode (`.arPlace`)** with `"arkit"` SF Symbol
3. **`SavedScan.init(name:placedProps:)`** for AR-only saves
4. **"AR View" button on saved scans**
5. **3-axis rotation gizmo rings** (red=X, green=Y, blue=Z) with fat invisible hit-test tubes
6. **Screen-space rotation direction** via 2D cross product
7. **Incremental rotation** using per-frame deltas
8. **Gizmo hidden during drag**
9. **Transform sync guards** (`isDragging` + `suppressTransformSync`)
10. **Compact AR controls** with two-row pill buttons
11. **Auto-open Size sheet** for unsized assets
12. **Upright placement on horizontal surfaces**

## Fixes Applied (Session 5 &mdash; March 24)

1. **Rotation ring hit detection:** `.all` search mode
2. **Props jumping during/after gestures:** `suppressTransformSync` through async gap
3. **Rotation direction:** `screenDragToRotationAngle` cross product
4. **Props laying flat on horizontal surfaces:** `uprightTransform` with synthetic horizontal normal
5. **Horizontal surface detection for estimated planes:** dot product threshold instead of anchor alignment

## Architecture Refactor (Session 6 &mdash; April 1)

**Major refactoring:**
1. **`PropInteractionHelper` extracted** &mdash; ~200 lines of duplicated coordinator logic moved to shared helper class. Both AR and offline coordinators delegate to it.
2. **Image caching** &mdash; `NSCache<NSUUID, UIImage>` with 50MB limit using decoded pixel cost, cache-first loading, eviction on delete.
3. **Async scan loading** &mdash; `ScanStore.loadAllAsync()` on background queue with pending mutation queue to prevent race conditions.
4. **AR session no longer pauses during gestures** &mdash; removed expensive `session.pause()`/`session.run(config)` on every drag.
5. **AR layout save updates existing scan** &mdash; `existingScanID` parameter prevents orphaned saves when editing props from saved scan detail.
6. **Label rendering deduplicated** &mdash; `RoomScanView.Room3DViewer` now calls `PropNodeBuilder.makeImageLabel` instead of local copies.
7. **Shared view helpers extracted** &mdash; `PlacedProp.isNewPresetSize(assetStore:)` and `PlacedProp.duplicated()` replace copy-pasted logic in both placement views.
8. **`endDrag()` centralized** in `PropInteractionHelper` &mdash; both coordinators call `helper.endDrag()`.

**Bug fixes:**
1. **Data race in ManualMeasureView** &mdash; `points.last` moved inside `DispatchQueue.main.async`
2. **ScanStore race condition** &mdash; `isLoaded` flag + `pendingMutations` queue replayed after load
3. **Ghost preview not resizing** &mdash; now tracks `ghostPresetWidth`/`ghostPresetHeight` and rebuilds on change
4. **Cache cost underestimated** &mdash; uses `cgImage.bytesPerRow * cgImage.height` not compressed JPEG bytes
5. **Silent fallthrough on deleted scan save** &mdash; `canUpdateExistingScan` computed property shows TextField when scan is gone
6. **HTML entity bug** &mdash; `"Event &amp; Premiere Planning"` &rarr; `"Event & Premiere Planning"`

**Dead code removed:**
- `ARPlaceSceneView.Coordinator.findAsset` (unused after helper extraction)
- `ManualMeasureView.debugLines` + all `newDebug` string-building (written but never displayed)
- `RoomScanManager.pendingScan` (declared but never read)
- `SurfaceMeasurement` / `SurfaceCategory` structs (never instantiated)
- `RoomScanManager.selectedMeasurement` (declared but never read)

**Code smell fixes:**
- `Thread.sleep(0.3)` removed from `CameraView` (`stopRunning()` is synchronous)
- Deprecated `onChange` single-argument form replaced with two-argument in `SavedScansView`
- `@State` vars moved from after `body` to top declaration block in `ARPlaceView`
- Inverted sheet binding `!show3D` replaced with dedicated `showMeasurements` state
- Double `gesture.location(in:)` call consolidated in `ARPlaceSceneView`
- `BulbDot` animation duration derived from `index % 7` instead of `Double.random()`

## AR Enhancements (Session 6 &mdash; April 1)

**Tier 1 &mdash; "It feels real":**
1. **Shadow planes** &mdash; soft radial gradient shadow beneath every placed prop. Cached texture, 60% opacity, sized 1.4x prop width. Applied in both `makeNode` and `updateNodeSize`.
2. **ARCoachingOverlayView** &mdash; Apple&rsquo;s built-in hand+phone animation for surface detection guidance. `.anyPlane` goal, auto-activates/hides.
3. **Haptic feedback** &mdash; light (select/ring tap), medium (placement), notification (first plane detected). Three `UIFeedbackGenerator` instances on the coordinator.
4. **Environment-responsive lighting** &mdash; prop materials changed from `.constant` to `.physicallyBased` with `roughness: 0.6`. Props darken in dim rooms, brighten in sunlight. Labels/gizmos remain `.constant`.

**Tier 2 &mdash; "It's easy to use":**
5. **Pinch to scale** &mdash; `UIPinchGestureRecognizer` with simultaneous recognition. Scales selected prop proportionally, clamped 0.05&ndash;5.0m. `Float.clamped(to:)` utility added.
6. **Placement bounce animation** &mdash; new props scale from 0.01 &rarr; 1.08 (0.2s) &rarr; 1.0 (0.12s) via `SCNAction.sequence` with `.easeOut` timing.
7. **Screenshot and share** &mdash; "Photo" button captures `ARSCNView.snapshot()` via `snapshotTrigger` counter, presents `UIActivityViewController` share sheet.
8. **Session interruption handling** &mdash; `sessionWasInterrupted`/`sessionInterruptionEnded` delegates. Shows "Session interrupted"/"Resuming..." status, re-runs config with `.resetTracking`.

**Tier 3 &mdash; "Polish":**
9. **Dot grid plane visualization** &mdash; tiling cyan dot pattern (4px dots at 16px spacing, 25% opacity) repeating every 20cm. Static cached texture. Replaces flat 8% cyan fill.
10. **Ghost preview breathing pulse** &mdash; continuous opacity animation (0.3 &rarr; 0.6 &rarr; 0.3) via `SCNAction.repeatForever`. Draws the eye to the placement point.

---

## Known Issues / Incomplete

1. **Non-LiDAR measurement accuracy:** Raycast depth estimation without LiDAR is unreliable for small measurements. Walk mode helps for larger distances.
2. **One wall missing** from 3D viewer in testing &mdash; possible RoomPlan detection or transform issue.
3. **No in-app media gallery** for browsing captured photos/videos. Storage is in place at `Documents/EventVision/`.
4. **SourceKit diagnostics** show cross-file resolution errors in the editor (e.g., "Cannot find type X in scope") but these are false positives &mdash; the full project builds successfully via `xcodebuild`.
5. **Pre-Session 4 scans have no USDZ:** Scans saved before Session 4 won&rsquo;t have a `.usdz` file, so the RoomPlan View toggle won&rsquo;t appear. Must rescan to get the USDZ export.
6. **Rotation rings still hard to grab in some orientations:** The invisible fat hit-test torus helps but some rings can still be tricky depending on camera angle.
7. **Props on horizontal surfaces may still face wrong direction** in some orientations &mdash; needs device testing.
8. **Session 6 AR enhancements need device testing:** Shadows, PBR lighting, coaching overlay, pinch-to-scale, bounce animation, dot grid planes, ghost pulse, screenshot/share, and haptics all compile but have not been tested on a physical device.

---

## Planned Features

### Next Up (Priority Order)
1. **Device test Session 6 AR enhancements** &mdash; Validate shadows, PBR lighting, coaching overlay, pinch gesture, bounce animation, screenshot/share, haptics on iPhone 14 Pro Max and iPhone 16
2. **Verify prop orientation on horizontal surfaces** &mdash; Confirm W&times;H always faces the user

### Future
3. **People occlusion** &mdash; `personSegmentationWithDepth` so props hide behind people
4. **LiDAR mesh occlusion** &mdash; Props hidden behind real furniture using scene reconstruction mesh
5. **Measurement overlays between props** &mdash; Show distance between placed props in AR
6. **Export/share scan results** &mdash; PDF or shareable format with room dimensions + placed props + screenshots
7. **In-app media gallery** &mdash; Browse captured photos/videos tagged by event/venue
8. **Web companion** &mdash; View scans, manage image library (React/Next.js)
9. **Android port** &mdash; ARCore + Kotlin

---

## Development Environment

- **Mac:** Xcode 26.3 (Build 17C529)
- **Simulators available:** iPhone 17 Pro, iPhone 17 Pro Max, iPad Air, etc. (iOS 26.3.1)
- **Physical devices tested:** iPhone 16 (no LiDAR), iPhone 14 Pro Max (LiDAR)
- **Apple Developer Team ID:** 5YT82K795W
- **Bundle ID:** com.eventvision.app
- **Deployment target:** iOS 17.0
- **Build command:** `xcodebuild -project EventVision.xcodeproj -scheme EventVision -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

---

## File Storage Layout

```
Documents/EventVision/
  Scans/
    {uuid}.json              - Saved scan data (surfaces + placed props with depth)
    {uuid}.usdz              - RoomPlan 3D model export (furniture, walls, etc.)
  Assets/
    assets.json              - Image asset manifest (includes vendor info, dimensions)
    presets.json             - Asset size presets manifest
    {uuid}.jpg               - Imported asset images
  {timestamp}.jpg            - Captured photos
  {timestamp}.mov            - Captured videos
```

---

## How to Resume

1. Open terminal, `cd /Users/michaeljenkins/Documents/Code/Event-Vision`
2. `open EventVision.xcodeproj`
3. Select physical device in Xcode device picker
4. Build and run (Cmd+R)
5. For LiDAR features, use iPhone 14 Pro Max
6. For non-LiDAR testing, use iPhone 16

### Where we left off (April 1, 2026 &mdash; Session 6)
- All features from Sessions 1&ndash;6 are built and **compiling successfully**
- Session 6 was a major session covering three phases:
  1. **Architecture refactor** &mdash; extracted `PropInteractionHelper` (shared coordinator logic), added image caching, async scan loading, fixed AR session drag performance, fixed save flow for existing scans
  2. **Bug fixes** &mdash; data race in ManualMeasureView, ScanStore race condition, ghost preview resize, cache cost calculation, deleted scan fallthrough, HTML entity bug, dead code removal, deprecated API cleanup
  3. **AR enhancements** (Amazon AR-level quality) &mdash; shadows, ARCoachingOverlayView, haptic feedback, PBR lighting, pinch-to-scale, placement bounce animation, screenshot/share, session interruption handling, dot grid planes, ghost breathing pulse
- **Needs device testing:** All Session 6 AR enhancements. Plug in iPhone 14 Pro Max (LiDAR) and iPhone 16 (no LiDAR) to validate shadows look natural, PBR lighting matches the room, haptics feel right, pinch-to-scale is responsive, coaching overlay appears/disappears correctly, and screenshot/share works.
- **Next priorities:** Device test everything, then move to people occlusion or export/share for the "send it to the client" workflow.
