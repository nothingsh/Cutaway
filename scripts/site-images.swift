// Draws the website's icons and its social preview image from the app's icon and the product
// picture, so that they can be made again when either changes.
// Usage: swift scripts/site-images.swift   (from the repository's root)
import AppKit

enum SiteImages {
    static let publicFolder = URL(fileURLWithPath: "site/public")
    static let appIcon = "App/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
    /// Where the icon's rounded square sits in the 1024-pixel image, measured from the top left; the
    /// rest is the transparent margin and shadow that macOS icons keep.
    static let tile = CGRect(x: 100, y: 90, width: 824, height: 824)
    /// How far in from the tile's edges a square leaves out the rounded corners.
    static let cornerInset: CGFloat = 56

    static func iconCrop(_ rect: CGRect) -> NSImage {
        guard let image = NSImage(contentsOfFile: appIcon)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.width == 1024, let cropped = image.cropping(to: rect)
        else { fatalError("site-images: cannot read a 1024-pixel \(appIcon)") }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    static func load(_ path: String) -> NSImage {
        guard let image = NSImage(contentsOf: publicFolder.appendingPathComponent(path)) else {
            fatalError("site-images: cannot read site/public/\(path)")
        }
        return image
    }

    static func write(_ name: String, width: Int, height: Int, draw: (CGRect) -> Void) {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { fatalError("site-images: cannot make a \(width)×\(height) bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("site-images: cannot encode \(name)")
        }
        do {
            try data.write(to: publicFolder.appendingPathComponent(name))
        } catch {
            fatalError("site-images: cannot write \(name): \(error)")
        }
        print("site-images: wrote site/public/\(name)")
    }

    static func run() {
        let logo = iconCrop(tile)
        let product = load("media/home-overview-light.png")

        // The logo beside the site's name, and the browser tab's icon: the rounded square.
        for (name, size) in [("logo.png", 128), ("favicon.png", 64)] {
            write(name, width: size, height: size) { bounds in
                logo.draw(in: bounds)
            }
        }
        // The home screen rounds the corners itself and shows transparent ones as black, so this one
        // fills the whole square.
        write("apple-touch-icon.png", width: 180, height: 180) { bounds in
            iconCrop(tile.insetBy(dx: cornerInset, dy: cornerInset)).draw(in: bounds)
        }

        // The social preview: the name and the line on the left, the product leaning out on the right.
        write("social.png", width: 1200, height: 630) { bounds in
            NSColor(srgbRed: 0.965, green: 0.965, blue: 0.973, alpha: 1).setFill()
            bounds.fill()

            logo.draw(in: CGRect(x: 72, y: 420, width: 96, height: 96))

            // Each line is drawn from its lower left corner; the context is not flipped.
            func line(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: CGPoint) {
                NSAttributedString(string: string, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: color,
                ]).draw(at: point)
            }

            let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
            let grey = NSColor(srgbRed: 0.27, green: 0.27, blue: 0.29, alpha: 1)
            line("Cutaway", size: 64, weight: .bold, color: ink, at: CGPoint(x: 72, y: 318))
            line("Inspect iOS interfaces,", size: 36, weight: .semibold, color: ink, at: CGPoint(x: 72, y: 250))
            line("layer by layer.", size: 36, weight: .semibold, color: ink, at: CGPoint(x: 72, y: 204))
            line("A free Mac app · macOS 14 or later", size: 22, weight: .regular, color: grey,
                 at: CGPoint(x: 72, y: 110))

            let shot = CGRect(x: 560, y: 70, width: 760, height: 760 * product.size.height / product.size.width)
            // The product picture is the window with its own rounded corners, 2.75% of its width.
            let radius = shot.width * 0.0275
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
            shadow.shadowBlurRadius = 40
            shadow.shadowOffset = CGSize(width: 0, height: -12)
            shadow.set()
            NSBezierPath(roundedRect: shot, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: shot, xRadius: radius, yRadius: radius).addClip()
            product.draw(in: shot)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

SiteImages.run()
