import AuralCore
import SwiftUI

/// Colors from the design reference (docs/design-2.png).
enum Theme {
    /// Warm peach accent: progress ring, knob, time highlight, heart, active toggles.
    static let accent = Color(red: 0xF0 / 255, green: 0xB8 / 255, blue: 0x78 / 255)

    /// Icons that are not hovered are slightly see-through.
    static let iconOpacity = 0.7
    /// Icons that are not highlighted: white, slightly see-through.
    static let icon = Color.white.opacity(iconOpacity)

    /// Opacity of secondary white text (artist, subtitles). With the system's
    /// Increase Contrast setting it is close to full white.
    static func secondaryOpacity(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.85 : 0.6
    }
    /// Icons brighten to full white on hover with this timing.
    static let hoverAnimation = Animation.easeOut(duration: 0.15)

    /// Used until the first cover has loaded: the design's dark slate.
    static let fallbackCover = ArtworkColor(red: 0.20, green: 0.27, blue: 0.30)

    /// Vertical gradient tinted with the cover's average color. The color is
    /// kept saturated but darkened, so white text stays readable on any cover.
    static func background(for cover: ArtworkColor?) -> LinearGradient {
        let (hue, saturation, _) = hsb(cover ?? fallbackCover)
        let top = Color(hue: hue, saturation: min(max(saturation, 0.25), 0.65), brightness: 0.48)
        let bottom = Color(hue: hue, saturation: min(max(saturation, 0.25), 0.65) * 0.9, brightness: 0.20)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// RGB → hue, saturation, brightness (all 0…1).
    private static func hsb(_ color: ArtworkColor) -> (Double, Double, Double) {
        let maxValue = max(color.red, color.green, color.blue)
        let minValue = min(color.red, color.green, color.blue)
        let delta = maxValue - minValue
        guard delta > 0.0001 else { return (0, 0, maxValue) }

        var hue: Double
        if maxValue == color.red {
            hue = (color.green - color.blue) / delta
        } else if maxValue == color.green {
            hue = 2 + (color.blue - color.red) / delta
        } else {
            hue = 4 + (color.red - color.green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maxValue, maxValue)
    }
}

/// `mm:ss` with two-digit minutes, as in the design (`01:23`).
func formatTime(_ milliseconds: Int) -> String {
    let seconds = max(0, milliseconds / 1000)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
