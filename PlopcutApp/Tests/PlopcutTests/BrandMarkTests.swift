import AppKit
import Testing
@testable import Plopcut

@MainActor
@Suite struct BrandMarkTests {
    /// Every shape stays inside the cropped view box, so nothing is clipped at 16, 18 or 72 pt (spec 5.1).
    @Test func shapesFitTheViewBox() {
        #expect(BrandMark.viewBox.contains(BrandMark.letter.boundingBoxOfPath))
        for accent in BrandMark.Accent.allCases {
            #expect(BrandMark.viewBox.contains(BrandMark.accent(accent).boundingBoxOfPath))
        }
    }

    /// The p spans the stem's left edge to the bowl's outer edge, as drawn by the SVG (stem x 18…30, bowl 18…60).
    @Test func letterMatchesTheSpecGeometry() {
        let box = BrandMark.letter.boundingBoxOfPath
        #expect(abs(box.minX - 18) < 0.01 && abs(box.maxX - 60) < 0.01)
        #expect(abs(box.minY - 19) < 0.01 && abs(box.maxY - 82) < 0.01)
    }

    // T-01: the system tints the menu bar image in light, dark and highlighted states.
    @Test func menuBarImagesAreEighteenPointTemplates() throws {
        for accent in BrandMark.Accent.allCases {
            let image = BrandMark.templateImage(accent)
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
            let rep = try #require(image.bitmap(scale: 2))
            #expect(rep.pixelsWide == 36)
            #expect(rep.hasInk(atX: 4, y: 18))  // the stem
        }
    }

    @Test func viewBoxFitsTheLargestCenteredSquare() {
        let t = BrandMark.transform(fitting: CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(CGPoint(x: 10, y: 10).applying(t) == CGPoint(x: 10, y: 0))
        #expect(CGPoint(x: 90, y: 90).applying(t) == CGPoint(x: 90, y: 80))
    }
}

private extension NSImage {
    func bitmap(scale: CGFloat) -> NSBitmapImageRep? {
        let pixels = Int(size.width * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

private extension NSBitmapImageRep {
    func hasInk(atX x: Int, y: Int) -> Bool { (colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
}
