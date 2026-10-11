import CoreGraphics
import CutawayRender
import CutawayTestSupport
import Foundation
import ImageIO
import XCTest

/// Whole-image comparison with the approved pictures in `Baselines/`. The tests only read
/// `Baselines/`; what they draw goes to `BaselineCandidates/`, which is not checked in, for a
/// person to look at.
enum Baselines {
    static let directory = Fixtures.repositoryRoot.appendingPathComponent("Baselines")
    static let candidates = Fixtures.repositoryRoot.appendingPathComponent("BaselineCandidates")
    /// Per channel, 0–255.
    static let tolerance = 2
}

enum PNGError: Error {
    case unreadable(URL)
    case unwritable(String)
}

/// The pixels of the PNG files.
private enum PNGPixels {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    /// BGRA in memory: 32-bit little endian with alpha first, premultiplied.
    static let bgra = CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue
}

func pngData(_ image: RenderedImage) throws -> Data {
    guard let provider = CGDataProvider(data: image.bytes as CFData),
          let cgImage = CGImage(
              width: image.pixelWidth, height: image.pixelHeight, bitsPerComponent: 8,
              bitsPerPixel: 32, bytesPerRow: image.pixelWidth * 4, space: PNGPixels.srgb,
              bitmapInfo: CGBitmapInfo(rawValue: PNGPixels.bgra), provider: provider, decode: nil,
              shouldInterpolate: false, intent: .defaultIntent)
    else { throw PNGError.unwritable("no image") }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, "public.png" as CFString, 1, nil)
    else { throw PNGError.unwritable("no destination") }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { throw PNGError.unwritable("finalize") }
    return data as Data
}

func readPNG(_ url: URL) throws -> RenderedImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(
              data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
              bytesPerRow: cgImage.width * 4, space: PNGPixels.srgb, bitmapInfo: PNGPixels.bgra)
    else { throw PNGError.unreadable(url) }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    guard let pixels = context.data else { throw PNGError.unreadable(url) }
    return RenderedImage(
        pixelWidth: cgImage.width, pixelHeight: cgImage.height,
        bytes: Data(bytes: pixels, count: cgImage.width * cgImage.height * 4))
}

private func writeCandidate(_ image: RenderedImage, fileName: String) throws -> URL {
    try FileManager.default.createDirectory(
        at: Baselines.candidates, withIntermediateDirectories: true)
    let url = Baselines.candidates.appendingPathComponent(fileName)
    try pngData(image).write(to: url)
    return url
}

/// Fails when `Baselines/<name>.png` is missing or differs from the image by more than the
/// tolerance anywhere, and leaves the drawing (and where it differs) in `BaselineCandidates/`.
func assertMatchesBaseline(
    _ image: RenderedImage, named name: String,
    file: StaticString = #filePath, line: UInt = #line
) throws {
    let baselineURL = Baselines.directory.appendingPathComponent("\(name).png")
    guard FileManager.default.fileExists(atPath: baselineURL.path) else {
        let candidate = try writeCandidate(image, fileName: "\(name).png")
        XCTFail(
            "there is no approved baseline \(name).png; the drawing is at \(candidate.path) "
                + "for a person to review", file: file, line: line)
        return
    }

    let baseline = try readPNG(baselineURL)
    guard baseline.pixelWidth == image.pixelWidth, baseline.pixelHeight == image.pixelHeight
    else {
        let actual = try writeCandidate(image, fileName: "\(name).actual.png")
        XCTFail(
            "\(name).png is \(baseline.pixelWidth) × \(baseline.pixelHeight), the drawing is "
                + "\(image.pixelWidth) × \(image.pixelHeight); see \(actual.path)",
            file: file, line: line)
        return
    }

    var differing = 0
    var largest = 0
    var diff = [UInt8](repeating: 0, count: image.bytes.count)
    let actual = [UInt8](image.bytes), expected = [UInt8](baseline.bytes)
    for offset in stride(from: 0, to: actual.count, by: 4) {
        var worst = 0
        for channel in 0..<4 {
            worst = max(worst, abs(Int(actual[offset + channel]) - Int(expected[offset + channel])))
        }
        largest = max(largest, worst)
        if worst > Baselines.tolerance {
            differing += 1
            diff[offset..<(offset + 4)] = [0, 0, 255, 255]  // red where it differs
        } else {
            // The drawing, dimmed, where it agrees.
            diff[offset] = actual[offset] / 3
            diff[offset + 1] = actual[offset + 1] / 3
            diff[offset + 2] = actual[offset + 2] / 3
            diff[offset + 3] = 255
        }
    }
    guard differing > 0 else { return }
    let actualURL = try writeCandidate(image, fileName: "\(name).actual.png")
    _ = try writeCandidate(
        RenderedImage(
            pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, bytes: Data(diff)),
        fileName: "\(name).diff.png")
    XCTFail(
        "\(differing) pixels differ from \(name).png by more than \(Baselines.tolerance), "
            + "by up to \(largest); see \(actualURL.path) and the .diff.png beside it",
        file: file, line: line)
}
