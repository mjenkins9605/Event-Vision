import SwiftUI

struct AssetDetailView: View {
    let asset: ImageAsset
    @EnvironmentObject var assetStore: AssetStore
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var vendorName: String = ""
    @State private var vendorAddress: String = ""
    @State private var vendorPhone: String = ""
    @State private var notes: String = ""
    @State private var quotes: [VendorQuote] = []
    @State private var hasPhysicalDimensions: Bool = false
    @State private var physicalWidth: Float = 0.5
    @State private var physicalHeight: Float = 0.5
    @State private var physicalDepth: Float = 0
    @State private var showDeleteConfirm = false
    @State private var image: UIImage?

    var body: some View {
        Form {
            // Image preview
            Section {
                HStack {
                    Spacer()
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    } else {
                        ProgressView()
                            .frame(height: 200)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // Name
            Section("Name") {
                TextField("Asset name", text: $name)
            }

            // Physical Dimensions
            Section {
                Toggle("Set Physical Dimensions", isOn: $hasPhysicalDimensions)

                if hasPhysicalDimensions {
                    VStack(spacing: 12) {
                        DimensionSlider(label: "W", meters: $physicalWidth, range: 0.05...10.0)
                        DimensionSlider(label: "H", meters: $physicalHeight, range: 0.05...10.0)
                        DimensionSlider(label: "D", meters: $physicalDepth, range: 0...10.0, tint: .orange, allowZero: true)
                    }
                }
            } header: {
                Text("Physical Dimensions (W \u{00D7} H \u{00D7} D)")
            } footer: {
                Text("Width and height set the face size. Depth shows how far it extends from the wall (e.g., step &amp; repeat with carpet).")
            }

            // Vendor Info
            Section("Vendor") {
                HStack {
                    Text("Company")
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    TextField("Vendor name", text: $vendorName)
                }
                HStack {
                    Text("Address")
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    TextField("Street, City, State", text: $vendorAddress)
                }
                HStack {
                    Text("Phone")
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    TextField("Phone number", text: $vendorPhone)
                        .keyboardType(.phonePad)
                }
            }

            // Quotes
            Section {
                ForEach($quotes) { $quote in
                    QuoteRow(quote: $quote, onDelete: {
                        quotes.removeAll { $0.id == quote.id }
                    })
                }

                Button {
                    quotes.append(VendorQuote())
                } label: {
                    Label("Add Quote", systemImage: "plus.circle")
                }
            } header: {
                Text("Quotes")
            } footer: {
                Text("Track pricing quotes from vendors. Each quote can have an amount and a note.")
            }

            // Notes
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }

            // Delete
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Asset", systemImage: "trash")
                            .font(.headline)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Asset Details")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            image = assetStore.loadImage(for: asset)
            name = asset.name
            vendorName = asset.vendorName ?? ""
            vendorAddress = asset.vendorAddress ?? ""
            vendorPhone = asset.vendorPhone ?? ""
            notes = asset.notes ?? ""
            quotes = asset.quotes ?? []
            hasPhysicalDimensions = asset.physicalWidthMeters != nil
            physicalWidth = asset.physicalWidthMeters ?? 0.5
            physicalHeight = asset.physicalHeightMeters ?? (0.5 / asset.aspectRatio)
            physicalDepth = asset.physicalDepthMeters ?? 0
        }
        .onDisappear {
            saveChanges()
        }
        .alert("Delete Asset", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                assetStore.deleteAsset(asset)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \u{201C}\(asset.name)\u{201D}? This cannot be undone.")
        }
    }

    private func saveChanges() {
        var updated = asset
        updated.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? asset.name : name
        updated.vendorName = vendorName.isEmpty ? nil : vendorName
        updated.vendorAddress = vendorAddress.isEmpty ? nil : vendorAddress
        updated.vendorPhone = vendorPhone.isEmpty ? nil : vendorPhone
        updated.notes = notes.isEmpty ? nil : notes
        updated.quotes = quotes.isEmpty ? nil : quotes
        updated.physicalWidthMeters = hasPhysicalDimensions ? physicalWidth : nil
        updated.physicalHeightMeters = hasPhysicalDimensions ? physicalHeight : nil
        updated.physicalDepthMeters = hasPhysicalDimensions && physicalDepth > 0.01 ? physicalDepth : nil
        assetStore.updateAsset(updated)
    }
}

// MARK: - Quote Row

private struct QuoteRow: View {
    @Binding var quote: VendorQuote
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("$")
                    .foregroundColor(.gray)
                TextField("Amount", text: $quote.amount)
                    .keyboardType(.decimalPad)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            TextField("Note (e.g. bulk discount, rush fee)", text: $quote.note)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(quote.dateAdded, style: .date)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
