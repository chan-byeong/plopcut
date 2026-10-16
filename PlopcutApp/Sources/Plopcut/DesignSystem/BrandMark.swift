import AppKit
import SwiftUI

/// The "p." monogram (spec 5.1). Shapes use the mark's 100 × 100 space with `translate(-5 -6)` already applied,
/// y pointing down, and are cropped to `viewBox="10 10 80 80"`.
enum BrandMark {
    /// What sits in the dot's place. The menu bar uses all three; the color mark only uses `.dot`.
    enum Accent: CaseIterable { case dot, check, exclamation }

    static let viewBox = CGRect(x: 10, y: 10, width: 80, height: 80)
    static let graphite = Color(red: 0x26 / 255, green: 0x28 / 255, blue: 0x2C / 255)
    static let blue = Color(red: 0x4F / 255, green: 0x8C / 255, blue: 0xFF / 255)

    /// The p: the stem and the stroked bowl as one filled shape.
    static var letter: CGPath {
        let stem = CGPath(rect: CGRect(x: 18, y: 19, width: 12, height: 63), transform: nil)
        let bowl = CGPath(ellipseIn: CGRect(x: 24, y: 25, width: 30, height: 30), transform: nil)
            .copy(strokingWithWidth: 12, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        return stem.union(bowl)
    }

    /// The shape in the dot's place, as a filled shape.
    static func accent(_ accent: Accent) -> CGPath {
        switch accent {
        case .dot:
            return CGPath(ellipseIn: CGRect(x: 67.5, y: 46, width: 15, height: 15), transform: nil)
        case .check:
            let check = CGMutablePath()
            check.addLines(between: [CGPoint(x: 66, y: 53), CGPoint(x: 72.5, y: 59.5), CGPoint(x: 84, y: 45)])
            return check.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 10)
        case .exclamation:
            let bar = CGMutablePath()
            bar.addLines(between: [CGPoint(x: 75, y: 36), CGPoint(x: 75, y: 50)])
            let stroke = bar.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 10)
            return stroke.union(CGPath(ellipseIn: CGRect(x: 71.2, y: 55.2, width: 7.6, height: 7.6), transform: nil))
        }
    }

    /// Maps the view box onto the largest centered square in `rect` (y down).
    static func transform(fitting rect: CGRect) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let scale = side / viewBox.width
        return CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
    }

    /// The single-color menu bar image (18 pt). The system tints it, and the handler redraws it at every backing scale.
    static func templateImage(_ accent: Accent, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let transform = transform(fitting: rect)
            context.addPath(letter.copy(using: [transform]) ?? letter)
            context.addPath(Self.accent(accent).copy(using: [transform]) ?? Self.accent(accent))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The color mark for the empty Library (72 pt) and the Save Popup title (16 pt). In dark mode the p is white, as on
/// the app icon, because graphite disappears on a dark window (spec 5.1).
struct BrandMarkView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let transform = BrandMark.transform(fitting: CGRect(origin: .zero, size: size))
            context.fill(Path(BrandMark.letter).applying(transform), with: .color(colorScheme == .dark ? .white : BrandMark.graphite))
            context.fill(Path(BrandMark.accent(.dot)).applying(transform), with: .color(BrandMark.blue))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(L10n.t("appLogo"))
        .accessibilityAddTraits(.isImage)
    }
}
