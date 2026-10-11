import CutawayTestSupport
import CutawayWire
import Foundation
import XCTest

/// C-ARCH-01: the archive format of Resources/ARCHIVE.md.
final class ArchiveTests: XCTestCase {
    private let manifest = ArchiveManifest(
        protocolVersion: ProtocolVersion.current, cutawayVersion: "0.1.0",
        savedAt: Date(timeIntervalSince1970: 1_791_280_000))

    private func fixture(_ scenario: String, _ file: String) throws -> Data {
        try Fixtures.data(scenario: scenario, file: file)
    }

    /// Server frames of the fixtures, in archive order.
    private func fixturePayloads() throws -> [Data] {
        [
            try fixture("handshake", "02-s2c-hello.bin"),
            try fixture("app-icon", "02-s2c-app-icon.bin"),
            try fixture("hierarchy", "02-s2c-hierarchy.bin"),
            try fixture("layer-details", "02-s2c-chunk-0.bin"),
            try fixture("layer-details", "03-s2c-chunk-1.bin"),
            try fixture("layout-constraints", "02-s2c-chunk-0.bin"),
        ]
    }

    private func archive(
        _ payloads: [Data], manifest: ArchiveManifest? = nil, state: Data = Data()
    ) throws -> Data {
        var encoder = ArchiveEncoder()
        var data = encoder.header(manifest: manifest ?? self.manifest, state: state)
        for payload in payloads { data += try encoder.frame(payload) }
        data += encoder.trailer()
        return data
    }

    private func assertRefused(
        _ data: Data, as expected: ArchiveError, file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            _ = try ArchiveDecoder(data)
            XCTFail("the archive was accepted", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    private func assertDamaged(
        _ data: Data, file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            _ = try ArchiveDecoder(data)
            XCTFail("the archive was accepted", file: file, line: line)
        } catch {
            guard case .damaged = error else {
                XCTFail("expected damaged, got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// The bytes of an archive with its manifest replaced by `json`.
    private func archive(manifestJSON json: String) throws -> Data {
        var data = Data("CTWYARCH".utf8) + uint32(1)
        let manifest = Data(json.utf8)
        data += uint32(UInt32(manifest.count)) + manifest
        data += uint32(0)
        for payload in try fixturePayloads().prefix(3) {
            data += uint32(UInt32(payload.count)) + payload
        }
        data += uint32(0) + uint32(3) + Data("CTWYDONE".utf8)
        return data
    }

    // MARK: - Reading back

    func test_C_ARCH_01_aFixtureArchiveReadsBackFrameForFrame() throws {
        let payloads = try fixturePayloads()
        let state = Data("{\"selected\":3}".utf8)
        let decoder = try ArchiveDecoder(try archive(payloads, state: state))

        XCTAssertEqual(decoder.manifest, manifest)
        XCTAssertEqual(decoder.state, state)
        XCTAssertEqual(decoder.payloads, payloads)

        guard case .hello(let hello) = try FrameCodec.decode(payloads[0]).body,
              case .appIcon(let icon) = try FrameCodec.decode(payloads[1]).body,
              case .hierarchy(let hierarchy) = try FrameCodec.decode(payloads[2]).body
        else {
            XCTFail("the fixtures are not what this test expects")
            return
        }
        XCTAssertEqual(decoder.hello, hello)
        XCTAssertEqual(decoder.hello.app?.name, "Demo")
        XCTAssertEqual(decoder.appIcon, icon)
        XCTAssertEqual(decoder.hierarchy, hierarchy)
        XCTAssertEqual(decoder.hierarchy.nodes.count, 9)

        XCTAssertEqual(decoder.chunkCount, 3)
        for index in 0..<3 {
            guard case .layerDetailsChunk(let chunk) = try FrameCodec.decode(payloads[3 + index]).body
            else {
                XCTFail("fixture \(3 + index) is not a chunk")
                return
            }
            XCTAssertEqual(try decoder.chunk(at: index), chunk)
        }
        XCTAssertEqual(try decoder.chunk(at: 2).details.map(\.layerID), [3, 4, 9, 8, 99])
    }

    func test_C_ARCH_01_anArchiveWithoutDetailsReadsBack() throws {
        let payloads = Array(try fixturePayloads().prefix(3))
        let decoder = try ArchiveDecoder(try archive(payloads))
        XCTAssertEqual(decoder.chunkCount, 0)
        XCTAssertEqual(decoder.state, Data())
        XCTAssertEqual(decoder.payloads, payloads)
    }

    func test_C_ARCH_01_theEncoderRefusesFramesTheFormatCannotHold() {
        var encoder = ArchiveEncoder()
        XCTAssertThrowsError(try encoder.frame(Data()))
        XCTAssertThrowsError(
            try encoder.frame(Data(count: FrameCodec.maximumFrameLength + 1)))
    }

    // MARK: - Refusing

    func test_C_ARCH_01_aFileThatIsNotAnArchiveIsRefused() throws {
        assertRefused(Data(), as: .notAnArchive)
        assertRefused(Data("CTWYARC".utf8), as: .notAnArchive)

        var wrongMagic = try archive(try fixturePayloads())
        wrongMagic[0] = UInt8(ascii: "X")
        assertRefused(wrongMagic, as: .notAnArchive)

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        assertRefused(pngHeader, as: .notAnArchive)
    }

    func test_C_ARCH_01_aNewerFormatIsRefused() throws {
        var data = try archive(try fixturePayloads())
        data.replaceSubrange(8..<12, with: uint32(2))
        assertRefused(data, as: .newerFormat(2))
    }

    func test_C_ARCH_01_everyTruncationIsIncompleteAndNeverCrashes() throws {
        let data = try archive(try fixturePayloads())
        for length in 0..<data.count {
            let prefix = data.prefix(length)
            assertRefused(prefix, as: length < 8 ? .notAnArchive : .incomplete)
        }
    }

    func test_C_ARCH_01_aDamagedFrameIsRefused() throws {
        let payloads = try fixturePayloads()
        let good = try archive(payloads)

        // The root offset of the hierarchy frame, which comes after the header, the
        // manifest, the state and two frames, now points past the buffer.
        let headerLength = ArchiveEncoder().header(manifest: manifest, state: Data()).count
        let hierarchyStart = headerLength + 4 + payloads[0].count + 4 + payloads[1].count + 4
        var badFrame = good
        badFrame.replaceSubrange(
            hierarchyStart..<(hierarchyStart + 4), with: uint32(UInt32(payloads[2].count + 64)))
        assertDamaged(badFrame)

        // A frame length over the limit.
        var tooLong = good
        let firstFrame = headerLength
        tooLong.replaceSubrange(
            firstFrame..<(firstFrame + 4), with: uint32(UInt32(FrameCodec.maximumFrameLength + 1)))
        assertDamaged(tooLong)

        // The trailer's count is one too many.
        var wrongCount = good
        let count = good.count - 12
        wrongCount.replaceSubrange(count..<(count + 4), with: uint32(UInt32(payloads.count + 1)))
        assertDamaged(wrongCount)

        // The trailer's magic.
        var wrongEnd = good
        wrongEnd[good.count - 1] = UInt8(ascii: "X")
        assertDamaged(wrongEnd)

        // A byte after the trailer.
        assertDamaged(good + Data([0]))
    }

    func test_C_ARCH_01_aDamagedManifestIsRefused() throws {
        assertDamaged(try archive(manifestJSON: "not json"))
        assertDamaged(try archive(manifestJSON: "[]"))
        assertDamaged(try archive(manifestJSON: """
        {"protocol":{"major":0,"minor":5},"cutawayVersion":"0.1.0"}
        """))
        assertDamaged(try archive(manifestJSON: """
        {"protocol":{"major":0,"minor":"5"},"cutawayVersion":"0.1.0",\
        "savedAt":"2026-10-06T08:30:00Z"}
        """))
    }

    func test_C_ARCH_01_framesOutOfOrderAreRefused() throws {
        let payloads = try fixturePayloads()
        let streamEnd = try fixture("layer-details", "04-s2c-stream-end.bin")
        let clientHello = try fixture("handshake", "01-c2s-hello.bin")

        assertDamaged(try archive([payloads[2], payloads[0], payloads[1]]))
        assertDamaged(try archive(Array(payloads.prefix(3)) + [payloads[2]]))
        assertDamaged(try archive(Array(payloads.prefix(4)) + [streamEnd]))
        assertDamaged(try archive([clientHello] + payloads.dropFirst()))
        assertDamaged(try archive(Array(payloads.prefix(2))))
    }

    func test_C_ARCH_01_anotherProtocolMajorIsRefused() throws {
        let current = ProtocolVersion.current
        let other = Version(major: current.major + 1, minor: 0)
        var manifest = self.manifest
        manifest.protocolVersion = other
        assertRefused(
            try archive(try fixturePayloads(), manifest: manifest),
            as: .differentProtocolMajor(other))
    }

    func test_C_ARCH_01_aNewerProtocolMinorIsRefused() throws {
        let current = ProtocolVersion.current
        let newer = Version(major: current.major, minor: current.minor + 1)
        var manifest = self.manifest
        manifest.protocolVersion = newer
        assertRefused(
            try archive(try fixturePayloads(), manifest: manifest),
            as: .newerProtocolMinor(newer))

        // An older minor version reads.
        guard current.minor > 0 else { return }
        manifest.protocolVersion = Version(major: current.major, minor: current.minor - 1)
        XCTAssertEqual(
            try ArchiveDecoder(try archive(try fixturePayloads(), manifest: manifest)).manifest,
            manifest)
    }

    /// A newer archive is refused for its version even when its frames would not verify here:
    /// a newer minor version may carry union members this reader does not know.
    func test_C_ARCH_01_theVersionIsCheckedBeforeTheFrames() throws {
        let current = ProtocolVersion.current
        let newer = Version(major: current.major, minor: current.minor + 1)
        var manifest = self.manifest
        manifest.protocolVersion = newer
        var payloads = Array(try fixturePayloads().prefix(3))
        payloads.append(Data(repeating: 0xEE, count: 16))
        assertRefused(try archive(payloads, manifest: manifest), as: .newerProtocolMinor(newer))
    }

    func test_C_ARCH_01_unknownManifestKeysAreIgnored() throws {
        let current = ProtocolVersion.current
        let decoder = try ArchiveDecoder(try archive(manifestJSON: """
        {"protocol":{"major":\(current.major),"minor":\(current.minor),"patch":3},\
        "cutawayVersion":"0.1.0","savedAt":"2026-10-06T08:30:00Z","layerCount":9}
        """))
        XCTAssertEqual(decoder.manifest.protocolVersion, current)
        XCTAssertEqual(decoder.manifest.cutawayVersion, "0.1.0")
        XCTAssertEqual(
            decoder.manifest.savedAt,
            ISO8601DateFormatter().date(from: "2026-10-06T08:30:00Z"))
    }
}
