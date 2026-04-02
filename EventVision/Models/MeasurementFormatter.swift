import Foundation

enum MeasurementFormatter {
    /// Convert meters to feet and inches string.
    /// Always carries 12" into the next foot (no "7'12"" — becomes "8'").
    static func feetInches(_ meters: Float) -> String {
        let totalInches = meters * 39.3701
        var feet = Int(totalInches) / 12
        var inches = round(totalInches - Float(feet * 12))

        // Carry over if rounding pushed inches to 12
        if inches >= 12 {
            feet += 1
            inches = 0
        }

        if feet == 0 {
            return String(format: "%.0f\"", inches)
        }
        if inches == 0 {
            return "\(feet)\u{2032}"
        }
        return "\(feet)\u{2032}\(Int(inches))\""
    }

    /// Split meters into feet and inches components.
    static func toFeetInches(_ meters: Float) -> (feet: Int, inches: Int) {
        let totalInches = meters * 39.3701
        var feet = Int(totalInches) / 12
        var inches = Int(round(totalInches - Float(feet * 12)))
        if inches >= 12 { feet += 1; inches = 0 }
        return (feet, inches)
    }

    /// Convert feet and inches back to meters.
    static func toMeters(feet: Int, inches: Int) -> Float {
        let totalInches = Float(feet * 12 + inches)
        return totalInches / 39.3701
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
