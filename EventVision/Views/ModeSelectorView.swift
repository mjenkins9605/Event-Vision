import SwiftUI

struct ModeSelectorView: View {
    @Binding var selectedMode: CaptureMode

    var body: some View {
        HStack(spacing: 16) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 22))
                        Text(mode.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selectedMode == mode ? .white : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        selectedMode == mode
                            ? Color.white.opacity(0.15)
                            : Color.clear
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
    }
}
