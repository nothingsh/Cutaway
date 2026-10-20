import CutawayTestSupport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-04: opening an archive file, and why one cannot be opened.
final class ArchiveFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ data: Data, as name: String = "Demo.cutaway") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func openError(_ url: URL) async -> ArchiveOpenError? {
        do {
            _ = try await ArchiveFile.open(url)
            return nil
        } catch {
            return error
        }
    }

    func test_C_ARCH_04_anArchiveOpensWithItsAppAndState() async throws {
        var state = ArchiveState()
        state.selected = 3
        state.previewMode = .threeD
        let url = try write(try Fixtures.archive(state: state.encoded()))

        let archive = try await ArchiveFile.open(url)
        XCTAssertEqual(archive.url, url)
        XCTAssertEqual(archive.app.name, "Demo")
        XCTAssertEqual(archive.icon?.pixelWidth, 2)
        XCTAssertEqual(archive.state, state)
        XCTAssertEqual(archive.manifest.cutawayVersion, "0.1.0")
        let hierarchy = try await archive.source.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 14)
    }

    func test_C_PREF_02_anArchiveWithoutASpacingOpensWithTheSettingsSpacing() async throws {
        let url = try write(try Fixtures.archive(state: Data(#"{"mode": "3d"}"#.utf8)))
        var start = InspectionStart()
        start.layerSpacing = 80
        let archive = try await ArchiveFile.open(url, start: start)
        XCTAssertEqual(archive.state.previewMode, .threeD)
        XCTAssertEqual(archive.state.cameras.threeD.layerSpacing, 80)
    }

    func test_C_ARCH_04_eachKindOfBadFileIsReportedAsSuch() async throws {
        let missing = directory.appendingPathComponent("Missing.cutaway")
        guard case .unreadable = await openError(missing) else {
            XCTFail("a missing file is not unreadable")
            return
        }

        let good = try Fixtures.archive()
        var error = await openError(try write(Data("hello".utf8), as: "Text.cutaway"))
        XCTAssertEqual(error, .notAnArchive)
        error = await openError(try write(good.prefix(good.count - 3), as: "Short.cutaway"))
        XCTAssertEqual(error, .incomplete)

        var damaged = good
        damaged[damaged.count - 1] = UInt8(ascii: "X")
        error = await openError(try write(damaged, as: "Damaged.cutaway"))
        XCTAssertEqual(error, .damaged)

        var newerFormat = good
        newerFormat.replaceSubrange(8..<12, with: [2, 0, 0, 0])
        error = await openError(try write(newerFormat, as: "Format.cutaway"))
        XCTAssertEqual(error, .newer)

        let current = ProtocolVersion.current
        error = await openError(try write(
            try Fixtures.archive(protocolVersion: Version(major: current.major, minor: current.minor + 1)),
            as: "Minor.cutaway"))
        XCTAssertEqual(error, .newer)
        error = await openError(try write(
            try Fixtures.archive(protocolVersion: Version(major: current.major + 1, minor: 0)),
            as: "Major.cutaway"))
        XCTAssertEqual(error, .otherMajor)
    }
}
