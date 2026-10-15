import CutawayTestSupport
import Foundation
import XCTest

/// The process's footprint, which `scripts/soak.sh` follows over many rounds (C-SCALE-02).
final class ProcessMemoryTests: XCTestCase {
    func test_C_SCALE_02_theFootprintGrowsWithMemoryInUse() throws {
        let before = try XCTUnwrap(ProcessMemory.footprint)
        XCTAssertGreaterThan(before, 0)
        let size = 64 << 20
        let block = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { block.deallocate() }
        // Touched with bytes that do not compress, so that the pages are charged.
        arc4random_buf(block, size)
        let after = try XCTUnwrap(ProcessMemory.footprint)
        XCTAssertGreaterThanOrEqual(after, before + UInt64(size) / 2, "\(before) to \(after)")
    }
}

/// The open files a test sees, to follow temporary files it does not name (C-SCALE-02).
final class OpenFilesTests: XCTestCase {
    func test_C_SCALE_02_aFileIsListedWhileItIsOpen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenFilesTests-\(UUID().uuidString)")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([1])))
        defer { try? FileManager.default.removeItem(at: url) }
        let resolved = url.resolvingSymlinksInPath().path
        func isListed() -> Bool {
            OpenFiles.paths().contains { $0 == resolved || $0.hasSuffix(url.lastPathComponent) }
        }
        XCTAssertFalse(isListed())
        let handle = try FileHandle(forReadingFrom: url)
        XCTAssertTrue(isListed(), "\(OpenFiles.paths())")
        try handle.close()
        XCTAssertFalse(isListed())
    }
}
