import SwiftUI

/// The only place colors live. Flat fills, no gradients.
enum Palette {
    static let surface = Color(red: 0.086, green: 0.094, blue: 0.094)   // charcoal
    static let ring = Color(red: 0.145, green: 0.157, blue: 0.157)      // wedge at rest
    static let ringEdge = Color(red: 0.235, green: 0.250, blue: 0.247)
    static let text = Color(red: 0.91, green: 0.89, blue: 0.86)         // ash
    static let textDim = Color(red: 0.91, green: 0.89, blue: 0.86).opacity(0.38)
    static let accent = Color(red: 0.247, green: 0.659, blue: 0.588)    // verdigris
    static let onAccent = Color(red: 0.05, green: 0.07, blue: 0.07)
    static let warn = Color(red: 0.84, green: 0.62, blue: 0.22)         // amber
}
