import SwiftUI

/// A dimension input that combines a slider with a tappable feet/inches label.
/// Tapping the label switches to manual text entry for feet and inches.
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

            if isEditing {
                manualInput
            } else {
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
        }
    }

    private var displayText: String {
        if allowZero && meters < 0.01 {
            return "None"
        }
        return MeasurementFormatter.feetInches(meters)
    }

    private var manualInput: some View {
        HStack(spacing: 2) {
            TextField("0", text: $feetText)
                .keyboardType(.numberPad)
                .frame(width: 28)
                .multilineTextAlignment(.trailing)
                .font(compact ? .caption : .subheadline)
                .monospacedDigit()
                .focused($focusedField, equals: .feet)
            Text("\u{2032}")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.gray)
            TextField("0", text: $inchesText)
                .keyboardType(.numberPad)
                .frame(width: 22)
                .multilineTextAlignment(.trailing)
                .font(compact ? .caption : .subheadline)
                .monospacedDigit()
                .focused($focusedField, equals: .inches)
            Text("\"")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.gray)

            Button {
                applyManualInput()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: compact ? 14 : 16))
            }
            .buttonStyle(.plain)
        }
        .frame(width: compact ? 54 : 60, alignment: .trailing)
        .onSubmit {
            applyManualInput()
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
