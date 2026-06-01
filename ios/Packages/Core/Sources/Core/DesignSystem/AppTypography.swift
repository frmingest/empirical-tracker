import SwiftUI

/// Typography scale mirroring the visual hierarchy on the web dashboard.
/// All sizes are relative to the user's Dynamic Type setting.
public extension Font {
    // MARK: - Display
    static let displayLarge  = Font.system(size: 34, weight: .bold,     design: .default)
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .default)

    // MARK: - Headlines
    static let headlineLarge  = Font.system(size: 22, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 17, weight: .semibold, design: .default)
    static let headlineSmall  = Font.system(size: 15, weight: .medium,   design: .default)

    // MARK: - Body
    static let bodyLarge  = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall  = Font.system(size: 13, weight: .regular, design: .default)

    // MARK: - Numeric (monospaced for biomarker values)
    static let numericLarge  = Font.system(size: 28, weight: .semibold, design: .monospaced)
    static let numericMedium = Font.system(size: 20, weight: .medium,   design: .monospaced)
    static let numericSmall  = Font.system(size: 13, weight: .regular,  design: .monospaced)

    // MARK: - Labels
    static let labelLarge  = Font.system(size: 13, weight: .medium,   design: .default)
    static let labelMedium = Font.system(size: 11, weight: .medium,   design: .default)
    static let labelSmall  = Font.system(size: 10, weight: .regular,  design: .default).uppercaseSmallCaps()
}
