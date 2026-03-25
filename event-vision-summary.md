# Event Vision - Project Summary

**Last updated:** March 24, 2026 (Session 5)
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
      MeasurementFormatter.swift      - Shared feet/inches formatting + conversion helpers
      SavedScan.swift                 - Codable model for persisted scans + CodableMatrix4x4
      ScanStore.swift                 - JSON + USDZ file persistence for saved scans
      ImageAsset.swift                - ImageAsset, PlacedProp, VendorQuote, AssetPreset models
      AssetStore.swift                - Image library + preset persistence (JPEG + JSON manifests)
      PropNodeBuilder.swift           - SCNNode creation, labels, footprints, rotation gizmo rings
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
      InteractiveRoom3DViewer.swift   - Placement-enabled 3D viewer with move, rotate, tap-to-place
      ARPlaceView.swift               - Live AR placement SwiftUI host (controls, save flow)
      ARPlaceSceneView.swift          - Live AR placement UIViewRepresentable + Coordinator
    Assets.xcassets/
    Preview Content/
```

---

## App Flow

### Home Page (`HomeView`)
- Marquee-style "EVENT VISION" title with twinkling light bulbs around each word
- "Event &amp; Premiere Planning" subtitle
- Three navigation cards:
  - **New Capture** &mdash; pushes to `CaptureFlowView` (AR Scan/Photo/Video/AR Place)
  - **Saved Scans** &mdash; pushes to `SavedScansView` (list of persisted scans)
  - **Asset Library** &mdash; pushes to `AssetLibraryView` (event image management)
- Camera does NOT open on app launch &mdash; user must tap into it

### Capture Flow (`CaptureFlowView`, formerly `ContentView`)
- Default mode is **AR Scan** (not photo)
- Mode selector at bottom: AR Scan | Photo | Video | AR Place
- Custom back button ("Home") stops camera session before dismissing
- Camera session and AR session handoff managed via completion handler + 0.3s delay
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
2. **Saved Scans &rarr; tap a scan &rarr; AR View** &mdash; loads existing placed props into the AR scene

**Flow:**
1. AR session starts with horizontal + vertical plane detection
2. Select an asset via "Asset" button &rarr; asset picker sheet
3. **Ghost preview** (translucent prop) follows screen center via per-frame ARKit raycasts
4. Tap a detected surface to place the prop
5. On **horizontal surfaces** (floor/table): prop stands upright facing the camera (uses synthetic horizontal normal toward camera instead of the floor&rsquo;s up normal)
6. On **vertical surfaces** (walls): prop places flush against the wall
7. If the asset has no physical dimensions set, the **Size sheet auto-opens** after placement so the user can dial in W/H/D immediately
8. Tap an existing prop to select it &rarr; 3-axis rotation rings appear
9. **Save Layout** button &rarr; name prompt &rarr; saves as `SavedScan` with empty room geometry and placed props only

**Compact controls (two rows):**
- Top row (when prop selected): Size | Copy | Delete | Preset
- Bottom row: Asset | Save Layout
- All buttons use `.caption` font with `.lineLimit(1)` and `.fixedSize()` to prevent text wrapping
- Size opens a half-sheet with W/H/D `DimensionSlider` components

**AR Scene Coordinator (`ARPlaceSceneView.Coordinator`):**
- Conforms to `ARSCNViewDelegate`, `ARSessionDelegate`, `UIGestureRecognizerDelegate`
- Ghost preview: per-frame raycast from screen center, translucent (0.4 opacity) prop node
- Tap to place: ARKit raycast &rarr; `PropNodeBuilder.surfaceAlignedTransform` (or `uprightTransform` for horizontal surfaces) &rarr; `PlacedProp` &rarr; `PropNodeBuilder.makeNode`
- Select / Move / Rotate: same patterns as `InteractiveRoom3DViewer` coordinator
- AR session paused during drag gestures, resumed on end
- `suppressTransformSync` flag prevents stale binding data from snapping props back after gesture ends

### Scan Persistence
- **Save:** After scan, tap green "Save" button &rarr; alert prompts for name &rarr; saved as JSON in `Documents/EventVision/Scans/{uuid}.json` **+ USDZ export** at `{uuid}.usdz`
- **AR-only saves:** `SavedScan(name:placedProps:)` creates a scan with empty surface arrays and just placed props (no room geometry, no USDZ)
- **USDZ export:** `CapturedRoom.export(to:)` is called automatically on every LiDAR scan save &mdash; preserves full RoomPlan model including detected furniture (tables, chairs)
- **View:** Home &rarr; Saved Scans &rarr; tap scan &rarr; 3D viewer with measurements
- **Delete:** Two-step: tap "Delete" &rarr; confirmation alert ("Are you sure?") &mdash; deletes both JSON and USDZ files
- **Data stored:** All surface dimensions + full `simd_float4x4` transforms for walls, doors, windows, openings, placed props, and USDZ 3D model

### Saved Scan Detail View (`SavedScanDetailView`)
- **RoomPlan View / 3D Measured toggle** &mdash; switches between USDZ model (with furniture, rotate/zoom) and measured view with dimension labels. Only appears if `.usdz` file exists for the scan.
- **List** button &mdash; opens measurements sheet
- **Place Props** &mdash; navigates to offline 3D prop placement
- **AR View** &mdash; navigates to live AR placement with scan&rsquo;s props pre-loaded
- **Delete** &mdash; with confirmation

### Prop Placement (Offline 3D)
1. Home &rarr; Saved Scans &rarr; tap a scan &rarr; tap "Place Props"
2. Tap "Choose Asset" &rarr; asset picker sheet &rarr; select an image (or preset)
3. Tap any wall/surface in the 3D viewer &rarr; prop appears flush against it, **always facing the camera** (normal auto-flipped if needed)
4. Tap "Done" in the status bar to **stop placement mode** &mdash; further taps won&rsquo;t add more props
5. Tap "Choose Asset" again to re-enter placement mode and add more
6. Tap an existing prop &rarr; yellow highlight + **3-axis rotation rings** appear &rarr; controls:
   - **Tap a ring** &mdash; rotates 45&deg; on that axis
   - **Drag along a ring** &mdash; continuous rotation with correct screen-space direction
   - **Red ring** (X-axis) &mdash; pitch rotation
   - **Green ring** (Y-axis) &mdash; yaw/turntable rotation
   - **Blue ring** (Z-axis) &mdash; roll/spin on wall
   - **Drag the prop body** (one finger) &mdash; moves it in 3D space
   - **W/H/D sliders** with manual feet/inches input (tap the label to type exact values)
   - **Duplicate** button &mdash; copies the prop offset to the right
   - **Remove** button &mdash; deletes the selected prop
   - **Save as Preset** button &mdash; appears when size differs from known presets
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
- **Physical Dimensions (W &times; H &times; D)** &mdash; toggle on/off, three `DimensionSlider` components:
  - Width and height set the face size when placed on a wall
  - Depth shows how far it extends from the wall (e.g., step &amp; repeat with red carpet)
  - Each slider can be tapped to manually enter feet and inches
- **Vendor** section &mdash; Company name, address, phone
- **Quotes** section &mdash; Multiple vendor quotes, each with $ amount, note, and date. Add/remove quotes.
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
- **New `init(name:placedProps:)` initializer** for AR-only placement sessions (empty surface arrays)

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
- Three `NavigationLink` cards for New Capture, Saved Scans, Asset Library

### CameraView.swift
- Live camera preview using `AVCaptureVideoPreviewLayer`
- `CameraManager` handles photo capture, video recording, session lifecycle
- `stopSession(completion:)` with completion handler for clean handoff to AR

### ManualMeasureView.swift (non-LiDAR devices)
- Uses `ARSCNView` (SceneKit) for AR measurement
- Walk mode (camera position) and Point mode (raycast)
- Multi-point measurement with segment distances + total

### RoomScanView.swift (LiDAR devices)
- Auto-detects LiDAR and routes to `LiDARScanView` or `ManualMeasureView`
- `RoomCaptureViewController` wrapper for RoomPlan
- `Room3DViewer` for 3D visualization with measurement labels &mdash; supports `showMeasurements` toggle to hide labels/edges
- `USDZRoomViewer` for loading and displaying exported `.usdz` files with full camera controls
- Post-scan buttons in 2&times;2 grid layout

### ARPlaceView.swift (Live AR Placement &mdash; SwiftUI Host)
- Hosts `ARPlaceSceneView` (the AR rendering layer)
- Manages all SwiftUI state: `placedProps`, `selectedPropID`, `selectedAsset`, `presetWidth/Height`, `showAssetPicker`, `showDimensions`, `showSaveAlert`, `trackingStatus`
- Accepts `initialProps: [PlacedProp]` for loading existing props from saved scans
- Compact two-row button layout using `arPillButton` helper with `.lineLimit(1)` + `.fixedSize()`
- Size sheet (`.presentationDetents([.medium])`) with W/H/D `DimensionSlider` components
- Auto-opens Size sheet when placing an asset without physical dimensions
- Save flow: name prompt &rarr; `SavedScan(name:placedProps:)` &rarr; `scanStore.save(scan)`

### ARPlaceSceneView.swift (Live AR Placement &mdash; UIViewRepresentable)
- `UIViewRepresentable` wrapping `ARSCNView`
- AR session: `ARWorldTrackingConfiguration` with horizontal + vertical plane detection, optional `.sceneDepth`
- **Ghost preview:** Per-frame raycast from screen center &rarr; translucent prop at aim point
- **Tap to place:** ARKit raycast &rarr; horizontal surface detection (dot product > 0.7 with up vector) &rarr; `uprightTransform` (facing camera) or `surfaceAlignedTransform` (flush against wall)
- **Coordinator** conforms to `ARSCNViewDelegate`, `ARSessionDelegate`, `UIGestureRecognizerDelegate`
- **Gesture handling:** Same patterns as `InteractiveRoom3DViewer` &mdash; tap for select/place/rotate-45&deg;, pan for move/drag-rotate
- **Transform sync guards:** `isDragging` and `suppressTransformSync` flags prevent `updateUIView` from overwriting gesture-driven transforms with stale binding data
- **Plane visualization:** Translucent cyan planes on detected surfaces
- `uprightTransform(at:cameraTransform:)` &mdash; places props standing upright on horizontal surfaces facing camera via `surfaceAlignedTransform` with a synthetic horizontal normal

### MeasurementFormatter.swift
- `feetInches(_ meters:)` &mdash; converts meters to `"7'3""` format
- `toFeetInches(_ meters:)` &mdash; splits meters into (feet, inches) tuple
- `toMeters(feet:inches:)` &mdash; converts feet/inches back to meters

### SavedScan.swift
- `SavedScan`, `SavedSurface`, `CodableMatrix4x4` models
- Backward-compatible decoding for all evolving fields
- **`init(name:placedProps:)` for AR-only saves** (no room geometry)

### ScanStore.swift
- JSON file-based storage: one `.json` file per scan in `Documents/EventVision/Scans/`
- **USDZ export:** `save(_:room:)` accepts optional `CapturedRoom` and calls `room.export(to:)` to save `.usdz` alongside JSON
- `usdzURL(for:)` returns the USDZ file URL if it exists for a given scan
- `delete(_:)` removes both `.json` and `.usdz` files
- Methods: `save(_:room:)`, `delete(_:)`, `usdzURL(for:)`, `loadAll()` on init

### AssetStore.swift
- JPEG file storage + `assets.json` manifest + `presets.json` manifest
- Methods: `importImage`, `loadImage`, `updateAsset`, `deleteAsset`
- Preset CRUD: `addPreset`, `deletePreset`, `presets(for:)`
- Cascade-deletes presets when parent asset is deleted

### ImageAsset.swift
- `ImageAsset` with vendor info, physical dimensions (W &times; H &times; D), custom encoder/decoder
- `VendorQuote` for tracking pricing quotes
- `PlacedProp` with depth support and backward-compatible decoding
- `AssetPreset` for reusable size configurations
- Legacy support: reads old `physicalLengthMeters` key as `physicalWidthMeters`

### PropNodeBuilder.swift
- `makeNode(for:image:assetName:)` &mdash; creates either:
  - **Flat plane** (SCNPlane) when depth = 0
  - **3D box** (SCNBox) when depth > 0, with image textured on front face (material index 0), gray sides
- `addFloorFootprint(to:prop:)` &mdash; semi-transparent red rectangle on floor showing depth coverage + depth label
- `updateNodeSize` &mdash; rebuilds geometry + label when sliders change
- `makePropLabel` &mdash; floating billboard label showing `"Asset Name &mdash; W &times; H &times; D"`
- `surfaceAlignedTransform` &mdash; orients props flush against walls
- `makeImageLabel` / `renderLabelImage` &mdash; shared label rendering (used for room measurements too)
- **`makeRotationGizmo(faceWidth:faceHeight:)`** &mdash; builds 3 color-coded SCNTorus rings (X=red, Y=green, Z=blue) with:
  - Visible thin ring (0.008 pipe radius) for aesthetics
  - Invisible fat ring (0.04 pipe radius) for easy hit testing
  - 4 arrow indicator billboards per ring at 90&deg; intervals
- **`rotationAxis(for:)`** &mdash; walks up node hierarchy to identify which ring axis was hit

### InteractiveRoom3DViewer.swift
- `UIViewRepresentable` with `Coordinator` (conforms to `UIGestureRecognizerDelegate`)
- **Tap gesture:** select existing props, place new ones on surfaces, or tap a rotation ring for 45&deg; rotation
- **Pan gesture:** context-sensitive based on what was tapped:
  - Drag on prop body &rarr; **move** (projects screen delta to world space via `projectPoint`/`unprojectPoint`)
  - Drag on a rotation ring &rarr; **axis rotation** using `screenDragToRotationAngle` for correct direction
  - Camera control temporarily disabled during drag to prevent conflicts
- **Rotation rings:** 3-axis gizmo (red=X, green=Y, blue=Z) replaces the old blue/orange handle buttons
- **Placement:** Normal is auto-flipped to face camera using `simd_dot` check against camera position
- **Hit test mode:** `.all` (not `.closest`) so rings behind prop faces are still detected
- **Transform sync guards:** `isDragging` and `suppressTransformSync` prevent `updateUIView` from overwriting gesture-driven transforms
- `screenDragToRotationAngle` &mdash; projects rotation axis to screen space, uses 2D cross product with drag vector for intuitive rotation direction
- `syncProps` diffs `propNodes` dict against `placedProps` binding &mdash; handles add, remove, size updates, and guarded transform sync
- `updateSelection` draws yellow highlight + rotation gizmo
- `commitTransform` captures final transform, writes to binding async, clears suppress flag after write
- Placement uses priority chain: preset dims > asset physical dims > 0.5m fallback

### SavedScansView.swift
- `PropPlacementView` &mdash; full placement UI with:
  - "Done" button in status bar to **exit placement mode** (clears selected asset)
  - "Choose Asset" to re-enter placement mode
  - `DimensionSlider` for W/H/D (compact mode)
  - Duplicate button (offsets copy along surface right axis)
  - Remove button
  - Save as Preset button (appears when size differs from all known presets/defaults)
  - Auto-saves on disappear
- `SavedScansView` &mdash; list of saved scans
- `SavedScanDetailView` &mdash; RoomPlan View / 3D Measured toggle + **Place Props** + **AR View** + List + Delete
- `SavedScanMeasurementsSheet` &mdash; full surface dimensions list

### AssetLibraryView.swift
- `PhotosPicker` integration for importing images
- Grid items are `NavigationLink`s to `AssetDetailView`
- Shows W &times; H &times; D badge when physical dimensions are set
- Context menu delete still available as shortcut

### AssetPickerSheet.swift
- Grid of assets + presets grouped beneath each asset
- Info button (&oplus;) opens `AssetDetailView` as sheet
- Preset selection passes dimensions through bindings
- Size badge on items with physical dimensions

### AssetDetailView.swift
- Full detail/edit form: image preview, name, W/H/D dimensions, vendor info, quotes, notes, delete
- `DimensionSlider` components for each dimension
- Quotes section with add/remove individual quotes
- Auto-saves on disappear via `assetStore.updateAsset()`

### DimensionSlider.swift
- Reusable component: slider + tappable feet/inches label
- Tap label &rarr; manual entry with separate feet and inches text fields + checkmark confirm
- `compact` mode for placement toolbar, normal mode for detail form
- `allowZero` for depth slider (shows "None" at 0)
- Clamps input to slider range, caps inches at 11

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

1. **Prop labels:** Floating billboard labels on every placed prop showing name + dimensions (W &times; H, or W &times; H &times; D when depth is set)
2. **Duplicate props:** Copy a placed prop offset to the right, preserving all dimensions including depth
3. **Resize props:** W/H/D sliders in placement toolbar with real-time 3D updates
4. **Manual dimension input:** Tap any dimension label to type exact feet/inches values (`DimensionSlider` component)
5. **Asset presets:** Save custom sizes as reusable presets, shown in asset picker grouped under parent asset
6. **Asset detail view:** Full edit screen with vendor info (company, address, phone), multiple pricing quotes with notes, and physical dimensions (W &times; H &times; D)
7. **Physical dimensions drive placement:** Assets with real-world dimensions auto-place at correct size (priority: preset > physical dims > 0.5m fallback)
8. **3D depth rendering:** Props with depth > 0 render as SCNBox (image on front, gray sides) + red floor footprint showing ground coverage + depth label
9. **Backward-compatible persistence:** All new fields use `decodeIfPresent`, legacy `physicalLengthMeters` key still reads correctly

## Features Added (Session 4 &mdash; March 22)

1. **Done button for placement mode:** After choosing an asset, a "Done" button appears in the status bar. Tapping it exits placement mode so further surface taps don&rsquo;t keep adding props. "Choose Asset" re-enters placement mode.
2. **SCNBox face order fix:** Asset image was rendering on the top face (depth &times; width) instead of the front face (width &times; height). Fixed material index from 4 to 0 &mdash; SCNBox face order is: front, right, back, left, top, bottom.
3. **RoomPlan View / 3D Measured toggle on saved scans:** Saved scan detail view now has a toggle between the USDZ RoomPlan model (with furniture, full rotate/zoom) and the 3D Measured view with dimension labels. Button only appears if a `.usdz` file exists.
4. **USDZ export on save:** `CapturedRoom` is exported to `.usdz` automatically on every scan save via `room.export(to:)`. Preserves all RoomPlan-detected objects including tables, chairs, and furniture. Stored alongside JSON at `{uuid}.usdz`.
5. **USDZ viewer (`USDZRoomViewer`):** SceneKit-based viewer that loads `.usdz` files with full camera rotation/zoom/pan controls.
6. **USDZ cleanup on delete:** Both `.json` and `.usdz` files are removed when deleting a scan.
7. **Post-scan 2&times;2 button grid:** After completing a LiDAR scan, the four buttons (RoomPlan View, List, Save, Rescan) are arranged in a 2&times;2 grid instead of a horizontal row for better readability.
8. **Prop move (drag):** One-finger drag on a selected prop moves it in 3D space. Uses `projectPoint`/`unprojectPoint` to map screen movement to world coordinates at the correct depth. Camera control temporarily disabled during drag.
9. **Prop rotation handles:** Two visual rotation handles appear when a prop is selected (blue Z-axis, orange Y-axis). Single-finger drag on either handle.
10. **Auto-face camera on placement:** When placing a prop, the surface normal is checked with `simd_dot` against the camera direction. If the normal points away from the camera (into the wall), it&rsquo;s flipped so the prop always faces the user on initial placement.
11. **Room3DViewer `showMeasurements` toggle:** `Room3DViewer` now accepts a `showMeasurements` parameter. Edge lines are tagged as `"measurementEdge"` and labels as `"measurementLabel"` &mdash; `updateUIView` toggles their `isHidden` property for instant show/hide without rebuilding the scene.

## Features Added (Session 5 &mdash; March 24)

1. **Live AR prop placement (`ARPlaceView` + `ARPlaceSceneView`):** Full live AR placement experience with ghost preview, tap-to-place, select/move/rotate, and save-as-scan flow. Two entry points: 4th tab in capture flow ("AR Place") and "AR View" button on saved scan detail.
2. **4th capture mode (`.arPlace`):** Added to `CaptureMode` enum with `"arkit"` SF Symbol. Mode selector spacing tightened from 24 to 16 for 4 tabs.
3. **`SavedScan.init(name:placedProps:)`:** Convenience initializer for AR-only placement sessions (empty surface arrays, no room geometry).
4. **"AR View" button on saved scans:** `SavedScanDetailView` now has a purple "AR View" `NavigationLink` that opens `ARPlaceView` with the scan&rsquo;s existing props pre-loaded.
5. **3-axis rotation gizmo rings:** Replaced the old blue/orange rotation handle buttons (in both offline and AR modes) with 3 color-coded SCNTorus rings:
   - Red (X-axis pitch), Green (Y-axis yaw), Blue (Z-axis roll)
   - Tap a ring = 45&deg; rotation, drag = continuous rotation
   - Each ring has a visible thin torus + invisible fat torus (0.04 pipe radius) for easy hit testing
   - 4 arrow indicator billboards per ring at 90&deg; intervals
   - Hit test mode changed from `.closest` to `.all` so rings behind prop faces are detected
6. **Screen-space rotation direction:** `screenDragToRotationAngle` projects the rotation axis to screen space and uses 2D cross product with drag vector to determine intuitive rotation sign &mdash; dragging "around" the axis always rotates the expected direction regardless of camera angle.
7. **Incremental rotation:** Drag rotation uses per-frame deltas (`lastDragLocation`) instead of cumulative translation, preventing floating-point drift and jumps.
8. **Gizmo hidden during drag:** Rings hide on drag start and show on drag end to prevent hit-test interference during gestures.
9. **Transform sync guards:** `isDragging` + `suppressTransformSync` flags in both coordinators prevent `updateUIView`/`syncProps` from overwriting gesture-driven node transforms with stale SwiftUI binding data. `suppressTransformSync` stays true through the async `commitTransform` gap.
10. **Compact AR controls:** Two-row button layout with `.caption` font, `.lineLimit(1)`, `.fixedSize()`. Dimension sliders moved to a half-sheet ("Size" button) instead of inline.
11. **Auto-open Size sheet:** When placing a prop whose asset has no physical dimensions set (and no preset selected), the Size sheet auto-opens so the user can set W/H/D immediately.
12. **Upright placement on horizontal surfaces:** Props placed on floors/tables stand upright facing the camera instead of laying flat. Detects horizontal surfaces via `dot(normal, up) > 0.7` and uses `uprightTransform` which passes a synthetic horizontal normal (toward camera) to `surfaceAlignedTransform`.

## Fixes Applied (Session 4 &mdash; March 22)

1. **SCNBox front face material:** Changed from index 4 to index 0 in both `makeNode` and `updateNodeSize` in `PropNodeBuilder.swift`
2. **`Room3DViewer` init missing parameter:** Custom `init(scan:)` didn&rsquo;t include `showMeasurements`, causing build failure. Added `showMeasurements: Bool = true` parameter to the saved-scan initializer.

## Fixes Applied (Session 5 &mdash; March 24)

1. **Rotation ring hit detection:** Changed SceneKit hit test from `.closest` to `.all` search mode so rotation rings behind prop faces are found.
2. **Props jumping during/after gestures:** Added `suppressTransformSync` flag that stays active through the async `commitTransform` gap, preventing stale binding data from snapping nodes back.
3. **Rotation direction:** Replaced `translation.x * 0.01` (always same sign) with `screenDragToRotationAngle` using projected axis cross product for intuitive direction from any camera angle.
4. **Props laying flat on horizontal surfaces:** `extractNormal` returned `(0,1,0)` for floors, causing `surfaceAlignedTransform` to orient the prop face-up. Fixed with `uprightTransform` using synthetic horizontal normal. Detection uses dot product threshold (> 0.7) instead of `ARPlaneAnchor.alignment` check (which failed for estimated planes with nil anchors).
5. **Horizontal surface detection for estimated planes:** `isHorizontal` check was `(result.anchor as? ARPlaneAnchor)?.alignment == .horizontal` which returned false for estimated planes (nil anchor). Changed to normal direction check: `abs(dot(normal, up)) > 0.7`.

---

## Known Issues / Incomplete

1. **Non-LiDAR measurement accuracy:** Raycast depth estimation without LiDAR is unreliable for small measurements. Walk mode helps for larger distances.
2. **One wall missing** from 3D viewer in testing &mdash; possible RoomPlan detection or transform issue.
3. **No in-app media gallery** for browsing captured photos/videos. Storage is in place at `Documents/EventVision/`.
4. **No export/share** for scan results or placement layouts.
5. **SourceKit diagnostics** show cross-file resolution errors in the editor (e.g., "Cannot find type X in scope") but these are false positives &mdash; the full project builds successfully via `xcodebuild`.
6. **Pre-Session 4 scans have no USDZ:** Scans saved before Session 4 won&rsquo;t have a `.usdz` file, so the RoomPlan View toggle won&rsquo;t appear. Must rescan to get the USDZ export.
7. **Rotation rings still hard to grab in some orientations:** The invisible fat hit-test torus helps but some rings can still be tricky depending on camera angle. May need further UX refinement (e.g., proximity-based selection or separate rotation mode toggle).
8. **Props on horizontal surfaces may still face wrong direction:** The `uprightTransform` uses `surfaceAlignedTransform` with a synthetic horizontal normal toward the camera. If this still shows W&times;D instead of W&times;H in some cases, may need to investigate whether `surfaceAlignedTransform` itself has an axis convention issue for certain orientations.

---

## Planned Features

### Next Up
1. **Refine rotation UX** &mdash; Further improve ring grab reliability, possibly add a rotation mode toggle or long-press to enter rotation
2. **Prop orientation fix verification** &mdash; Device test the horizontal surface placement to confirm W&times;H always faces the user

### Future
3. **Pinch to scale** &mdash; Pinch gesture for resizing (in addition to existing sliders)
4. **Web companion** &mdash; View scans, manage image library (React/Next.js)
5. **Android port** &mdash; ARCore + Kotlin
6. **In-app media gallery** &mdash; Browse captured photos/videos tagged by event/venue
7. **Export/share scan results** &mdash; PDF or shareable format with room dimensions + placed props

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

### Where we left off (March 24, 2026 &mdash; Session 5)
- All features from Sessions 1-5 are built and **compiling successfully**
- Session 5 added: live AR prop placement (two entry points), 3-axis rotation gizmo rings (replacing old blue/orange handles), compact AR controls with Size sheet, auto-open Size for unsized assets, upright placement on horizontal surfaces, transform sync guards for smooth gestures
- **Needs device testing:** Horizontal surface prop orientation (should show W&times;H facing camera, not W&times;D). If still wrong, `surfaceAlignedTransform` axis convention may need adjustment.
- **Rotation rings** work but can still be hard to grab in some orientations &mdash; may need UX refinement
- **Next priorities:** Verify prop orientation on device, refine rotation grab UX, then move to export/share or web companion
