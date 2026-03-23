# Event Vision - Project Summary

**Last updated:** March 22, 2026 (Session 4)
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
      CaptureMode.swift               - Enum: .arScan, .photo, .video (AR first)
      MeasurementFormatter.swift      - Shared feet/inches formatting + conversion helpers
      SavedScan.swift                 - Codable model for persisted scans + CodableMatrix4x4
      ScanStore.swift                 - JSON + USDZ file persistence for saved scans
      ImageAsset.swift                - ImageAsset, PlacedProp, VendorQuote, AssetPreset models
      AssetStore.swift                - Image library + preset persistence (JPEG + JSON manifests)
      PropNodeBuilder.swift           - SCNNode creation (flat plane or 3D box), labels, footprints
    Views/
      HomeView.swift                  - Home page with marquee title + navigation cards
      ModeSelectorView.swift          - Bottom tab bar for switching between AR Scan/Photo/Video
      CameraView.swift                - Camera preview + photo capture + video recording + save
      ManualMeasureView.swift         - ARKit manual measurement for non-LiDAR devices
      RoomScanView.swift              - LiDAR scanning + 3D viewer + USDZ viewer + save scan flow
      SavedScansView.swift            - Saved scans list, detail, prop placement + move/rotate
      AssetLibraryView.swift          - Image asset library (import, grid, tap to detail)
      AssetPickerSheet.swift          - Compact asset picker with presets + info button
      AssetDetailView.swift           - Asset detail/edit: vendor info, quotes, W x H x D dimensions
      DimensionSlider.swift           - Reusable slider + manual feet/inches input component
      InteractiveRoom3DViewer.swift   - Placement-enabled 3D viewer with move, rotate, tap-to-place
    Assets.xcassets/
    Preview Content/
```

---

## App Flow

### Home Page (`HomeView`)
- Marquee-style "EVENT VISION" title with twinkling light bulbs around each word
- "Event &amp; Premiere Planning" subtitle
- Three navigation cards:
  - **New Capture** &mdash; pushes to `CaptureFlowView` (AR/Photo/Video)
  - **Saved Scans** &mdash; pushes to `SavedScansView` (list of persisted scans)
  - **Asset Library** &mdash; pushes to `AssetLibraryView` (event image management)
- Camera does NOT open on app launch &mdash; user must tap into it

### Capture Flow (`CaptureFlowView`, formerly `ContentView`)
- Default mode is **AR Scan** (not photo)
- Mode selector at bottom: AR Scan | Photo | Video
- Custom back button ("Home") stops camera session before dismissing
- Camera session and AR session handoff managed via completion handler + 0.3s delay

### LiDAR Scan Flow (`LiDARScanView`)
1. User taps "Start Scan"
2. RoomPlan scanning UI appears (built-in coaching, real-time room detection)
3. User walks around the room, taps "Done"
4. Auto-switches to custom 3D measured viewer
5. Post-scan buttons in a **2&times;2 grid layout**:
   - Row 1: "3D Measured" / "RoomPlan View" toggle | "List" (surface sheet)
   - Row 2: "Save" (name prompt) | "Rescan"

### Scan Persistence
- **Save:** After scan, tap green "Save" button &rarr; alert prompts for name &rarr; saved as JSON in `Documents/EventVision/Scans/{uuid}.json` **+ USDZ export** at `{uuid}.usdz`
- **USDZ export:** `CapturedRoom.export(to:)` is called automatically on every save &mdash; preserves full RoomPlan model including detected furniture (tables, chairs)
- **View:** Home &rarr; Saved Scans &rarr; tap scan &rarr; 3D viewer with measurements
- **Delete:** Two-step: tap "Delete" &rarr; confirmation alert ("Are you sure?") &mdash; deletes both JSON and USDZ files
- **Data stored:** All surface dimensions + full `simd_float4x4` transforms for walls, doors, windows, openings, placed props, and USDZ 3D model

### Saved Scan Detail View (`SavedScanDetailView`)
- **RoomPlan View / 3D Measured toggle** &mdash; switches between USDZ model (with furniture, rotate/zoom) and measured view with dimension labels. Only appears if `.usdz` file exists for the scan.
- **List** button &mdash; opens measurements sheet
- **Place Props** &mdash; navigates to prop placement
- **Delete** &mdash; with confirmation

### Prop Placement (Offline 3D)
1. Home &rarr; Saved Scans &rarr; tap a scan &rarr; tap "Place Props"
2. Tap "Choose Asset" &rarr; asset picker sheet &rarr; select an image (or preset)
3. Tap any wall/surface in the 3D viewer &rarr; prop appears flush against it, **always facing the camera** (normal auto-flipped if needed)
4. Tap "Done" in the status bar to **stop placement mode** &mdash; further taps won&rsquo;t add more props
5. Tap "Choose Asset" again to re-enter placement mode and add more
6. Tap an existing prop &rarr; yellow highlight + **rotation handles** appear &rarr; controls:
   - **Drag the prop** (one finger) &mdash; moves it in 3D space
   - **Blue rotation handle** (right side) &mdash; drag to spin on the wall (Z-axis rotation around surface normal)
   - **Orange rotation handle** (below) &mdash; drag to turntable-rotate around Y-axis (face a different wall)
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

---

## What Each File Does

### EventVisionApp.swift
- Creates `ScanStore` and `AssetStore` as `@StateObject`
- Injects both as `.environmentObject()` to the view hierarchy

### ContentView.swift (CaptureFlowView)
- Owns the `CameraManager` as a `@StateObject`
- Switches between `CameraView` (photo/video) and `RoomScanView` (AR)
- Waits for camera session to fully stop before allowing AR mode (prevents freeze)
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

### MeasurementFormatter.swift
- `feetInches(_ meters:)` &mdash; converts meters to `"7'3""` format
- `toFeetInches(_ meters:)` &mdash; splits meters into (feet, inches) tuple
- `toMeters(feet:inches:)` &mdash; converts feet/inches back to meters

### SavedScan.swift
- `SavedScan`, `SavedSurface`, `CodableMatrix4x4` models
- Backward-compatible decoding for all evolving fields

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

### InteractiveRoom3DViewer.swift
- `UIViewRepresentable` with `Coordinator` (conforms to `UIGestureRecognizerDelegate`)
- **Tap gesture:** select existing props or place new ones on surfaces
- **Pan gesture:** context-sensitive based on what was tapped:
  - Drag on prop body &rarr; **move** (projects screen delta to world space via `projectPoint`/`unprojectPoint`)
  - Drag on blue handle &rarr; **Z-axis rotation** (spin on wall, around surface normal)
  - Drag on orange handle &rarr; **Y-axis rotation** (turntable spin to face different direction)
  - Camera control temporarily disabled during drag to prevent conflicts
- **Placement:** Normal is auto-flipped to face camera using `simd_dot` check against camera position
- **Rotation handles:** Blue circle (right of prop) for Z-rotation, orange circle (below prop) for Y-rotation &mdash; rendered as billboard-constrained SCNPlanes with SF Symbol icons
- `syncProps` diffs `propNodes` dict against `placedProps` binding &mdash; handles add, remove, size updates, and transform sync. Skips sync while dragging to prevent feedback loops.
- `updateSelection` draws yellow highlight + both rotation handles, reads dimensions from box or plane child nodes
- `commitTransform` writes updated `simd_float4x4` back to `placedProps` binding after gesture ends
- Placement uses priority chain: preset dims > asset physical dims > 0.5m fallback
- `presetWidth`/`presetHeight` properties for preset dimension pass-through

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
- `SavedScanDetailView` &mdash; RoomPlan View / 3D Measured toggle + Place Props / List / Delete
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
9. **Prop rotation handles:** Two visual rotation handles appear when a prop is selected:
   - **Blue handle** (right side of prop) &mdash; drag horizontally to rotate around the surface normal (Z-axis, spin on wall)
   - **Orange handle** (below prop) &mdash; drag horizontally to turntable-rotate around world Y-axis (face a different direction)
   - Handles are rendered as billboard-constrained SCNPlanes with SF Symbol icons on blue/orange circle backgrounds
   - Single-finger drag on either handle &mdash; much easier than the previous two-finger rotation gesture which was removed
10. **Auto-face camera on placement:** When placing a prop, the surface normal is checked with `simd_dot` against the camera direction. If the normal points away from the camera (into the wall), it&rsquo;s flipped so the prop always faces the user on initial placement.
11. **Room3DViewer `showMeasurements` toggle:** `Room3DViewer` now accepts a `showMeasurements` parameter. Edge lines are tagged as `"measurementEdge"` and labels as `"measurementLabel"` &mdash; `updateUIView` toggles their `isHidden` property for instant show/hide without rebuilding the scene.

## Fixes Applied (Session 4 &mdash; March 22)

1. **SCNBox front face material:** Changed from index 4 to index 0 in both `makeNode` and `updateNodeSize` in `PropNodeBuilder.swift`
2. **`Room3DViewer` init missing parameter:** Custom `init(scan:)` didn&rsquo;t include `showMeasurements`, causing build failure. Added `showMeasurements: Bool = true` parameter to the saved-scan initializer.

---

## Known Issues / Incomplete

1. **Non-LiDAR measurement accuracy:** Raycast depth estimation without LiDAR is unreliable for small measurements. Walk mode helps for larger distances.
2. **One wall missing** from 3D viewer in testing &mdash; possible RoomPlan detection or transform issue.
3. **No in-app media gallery** for browsing captured photos/videos. Storage is in place at `Documents/EventVision/`.
4. **Live AR prop placement** not built yet (see Planned Features below).
5. **No export/share** for scan results or placement layouts.
6. **SourceKit diagnostics** show cross-file resolution errors in the editor (e.g., "Cannot find type X in scope") but these are false positives &mdash; the full project builds successfully via `xcodebuild`.
7. **Pre-Session 4 scans have no USDZ:** Scans saved before Session 4 won&rsquo;t have a `.usdz` file, so the RoomPlan View toggle won&rsquo;t appear. Must rescan to get the USDZ export.

---

## Planned Features

### Next Up (designed, not yet built)
1. **Live AR prop placement** &mdash; Place event assets in real-time while at the venue using ARKit + camera. Will use `ARSCNView` with plane detection, ghost preview following raycast, tap to place. Shares `PlacedProp` model and `PropNodeBuilder` with offline mode.

### Future
2. **Pinch to scale** &mdash; Pinch gesture for resizing (in addition to existing sliders)
3. **Web companion** &mdash; View scans, manage image library (React/Next.js)
4. **Android port** &mdash; ARCore + Kotlin
5. **In-app media gallery** &mdash; Browse captured photos/videos tagged by event/venue
6. **Export/share scan results** &mdash; PDF or shareable format with room dimensions + placed props

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

### Where we left off (March 22, 2026 &mdash; Session 4)
- All features from Sessions 1-4 are built and **compiling successfully**
- Session 4 added: placement mode Done button, USDZ export/viewer for saved scans, RoomPlan View toggle, 2&times;2 post-scan button grid, prop move (drag), prop rotation handles (Z-axis + Y-axis), auto-face camera on placement, SCNBox face fix
- **Prop move/drag is now implemented** &mdash; removed from Known Issues
- **Needs device testing** of all Session 4 features (move, rotate, USDZ viewer, placement mode toggle)
- After device testing, the **next major feature** is **live AR prop placement**
