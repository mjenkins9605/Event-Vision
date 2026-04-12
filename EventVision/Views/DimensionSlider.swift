import SwiftUI

/// A dimension input that combines a slider with a tappable feet/inches label.
/// Tapping the label opens a larger popup with feet and inches fields.
struct DimensionSlider: View {
    let label: String
    @Binding var meters: Float
    var range: ClosedRange<Float> = 0.05...10.0
    var tint: Color = .blue
    var allowZero: Bool = false
    var compact: Bool = false

    @State private var isEditing = false
    @State private var feetText = ""
    @State private var inchesText = ""
    @FocusState private var focusedField: Field?

    private enum Field { case feet, inches }

    var body: some View {
        HStack {
            Text(label)
                .font(compact ? .caption : .subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .frame(width: compact ? 24 : 20, alignment: .leading)

            Slider(value: $meters, in: range)
                .tint(tint)

            Button {
                let parts = MeasurementFormatter.toFeetInches(meters)
                feetText = "\(parts.feet)"
                inchesText = "\(parts.inches)"
                isEditing = true
                focusedField = .feet
            } label: {
                Text(displayText)
                    .font(compact ? .caption : .subheadline)
                    .monospacedDigit()
                    .foregroundColor(compact ? .white : .primary)
                    .frame(width: compact ? 54 : 60, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isEditing {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { applyManualInput() }
            }
        }
        .sheet(isPresented: $isEditing) {
            manualInputSheet
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    private var displayText: String {
        if allowZero && meters < 0.01 {
            return "None"
        }
        return MeasurementFormatter.feetInches(meters)
    }

    private var manualInputSheet: some View {
        VStack(spacing: 20) {
            Text("Set \(label) Dimension")
                .font(.headline)
                .padding(.top, 40)

            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Feet")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("0", text: $feetText)
                        .keyboardType(.numberPad)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(width: 80, height: 50)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($focusedField, equals: .feet)
                }

                Text("\u{2032}")
                    .font(.title)
                    .foregroundColor(.gray)

                VStack(spacing: 6) {
                    Text("Inches")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("0", text: $inchesText)
                        .keyboardType(.numberPad)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(width: 80, height: 50)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($focusedField, equals: .inches)
                }

                Text("\"")
                    .font(.title)
                    .foregroundColor(.gray)
            }

            Button {
                applyManualInput()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .onAppear {
            focusedField = .feet
        }
    }

    private func applyManualInput() {
        let feet = Int(feetText) ?? 0
        let inches = min(Int(inchesText) ?? 0, 11)
        let result = MeasurementFormatter.toMeters(feet: feet, inches: inches)
        if allowZero {
            meters = max(result, 0)
        } else {
            meters = max(result, range.lowerBound)
        }
        meters = min(meters, range.upperBound)
        isEditing = false
        focusedField = nil
    }
}
