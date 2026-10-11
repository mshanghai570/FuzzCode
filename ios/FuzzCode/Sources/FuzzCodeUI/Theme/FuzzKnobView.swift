import SwiftUI

/// Tactile vintage stompbox gain / volume dial.
/// Allows setting values (e.g. Temperature, Timeout, Token Limit) with rotational feedback.
public struct FuzzKnobView: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let label: String
    public let unit: String
    
    @State private var dragAngle: Double = 0
    
    public init(value: Binding<Double>, range: ClosedRange<Double>, label: String, unit: String = "") {
        self._value = value
        self.range = range
        self.label = label
        self.unit = unit
    }
    
    private var normalizedProgress: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    
    // -135 deg to +135 deg dial rotation
    private var rotationDegrees: Double {
        -135.0 + (normalizedProgress * 270.0)
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer chassis ring with notch marks
                Circle()
                    .stroke(FuzzTheme.border, lineWidth: 3)
                    .frame(width: 64, height: 64)
                
                // Active arc
                Circle()
                    .trim(from: 0.125, to: 0.125 + CGFloat(normalizedProgress * 0.75))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [FuzzTheme.electricPurple, FuzzTheme.acidGreen]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 64, height: 64)
                
                // Center metallic knob body
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                
                // Indicator needle notch
                Rectangle()
                    .fill(FuzzTheme.acidGreen)
                    .frame(width: 3, height: 16)
                    .offset(y: -14)
                    .rotationEffect(.degrees(rotationDegrees))
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let deltaY = -gesture.translation.height * 0.005
                        let newVal = min(max(value + deltaY * (range.upperBound - range.lowerBound), range.lowerBound), range.upperBound)
                        if abs(newVal - value) > 0.01 {
                            FuzzTheme.playStompFeedback()
                        }
                        self.value = newVal
                    }
            )
            
            VStack(spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textSecondary)
                
                Text(String(format: range.upperBound > 10 ? "%.0f %@" : "%.2f %@", value, unit))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textPrimary)
            }
        }
    }
}
