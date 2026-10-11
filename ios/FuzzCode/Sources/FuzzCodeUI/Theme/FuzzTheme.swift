import SwiftUI
import AudioToolbox
import UIKit

/// FuzzCode Visual & Sensory Identity:
/// Underground alternative-rock and fuzz-pedal aesthetics.
/// Deep charcoal (#0B0C0E), Acid-Green (#22C55E), Electric-Purple (#8B5CF6).
public enum FuzzTheme {
    // Canvas & Surfaces
    public static let background = Color(red: 11/255, green: 12/255, blue: 14/255)
    public static let surface = Color(red: 18/255, green: 20/255, blue: 26/255)
    public static let surfaceRaised = Color(red: 26/255, green: 29/255, blue: 38/255)
    public static let border = Color(red: 35/255, green: 39/255, blue: 51/255)
    
    // Rock Accents
    public static let acidGreen = Color(red: 34/255, green: 197/255, blue: 94/255)
    public static let acidBright = Color(red: 74/255, green: 222/255, blue: 128/255)
    public static let electricPurple = Color(red: 139/255, green: 92/255, blue: 246/255)
    public static let purpleBright = Color(red: 168/255, green: 85/255, blue: 247/255)
    public static let clippingRed = Color(red: 239/255, green: 68/255, blue: 68/255)
    public static let warningAmber = Color(red: 245/255, green: 158/255, blue: 11/255)
    
    // Text Hierarchy
    public static let textPrimary = Color(red: 241/255, green: 245/255, blue: 249/255)
    public static let textSecondary = Color(red: 148/255, green: 163/255, blue: 184/255)
    public static let textMuted = Color(red: 100/255, green: 116/255, blue: 139/255)
    
    // Haptics & Feedback
    public static func playStompFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        // Play subtle metallic stomp click
        AudioServicesPlaySystemSound(1104)
    }
    
    public static func playSuccessFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
    
    public static func playErrorFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}

/// Fuzz Pedal Stomp Switch Button
public struct FuzzStompButton: View {
    public let title: String
    public let icon: String
    public let action: () -> Void
    
    public init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            FuzzTheme.playStompFeedback()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(FuzzTheme.acidGreen)
                    .shadow(color: FuzzTheme.acidGreen.opacity(0.3), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
