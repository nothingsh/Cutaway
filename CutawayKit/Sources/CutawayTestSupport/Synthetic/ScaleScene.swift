import CutawayWire
import Foundation

extension SyntheticScene {
    /// An archive of the scene as a capture writes one (Resources/ARCHIVE.md): the fixtures'
    /// server `Hello`, the icon, the hierarchy, then the details of the layers `holding` lets
    /// through, every part of each, `chunkSize` to a chunk, in tree order.
    public func archive(
        chunkSize: Int = 8, state: Data = Data(), holding: (UInt64) -> Bool = { _ in true }
    ) throws -> Data {
        let hierarchy = hierarchy()
        let details = details()
        var encoder = ArchiveEncoder()
        var data = encoder.header(
            manifest: ArchiveManifest(
                protocolVersion: ProtocolVersion.current, cutawayVersion: "0.1.0",
                savedAt: Date(timeIntervalSince1970: 1_791_280_000)),
            state: state)
        data += try encoder.frame(try Fixtures.data(scenario: "handshake", file: "02-s2c-hello.bin"))
        data += try encoder.frame(FrameCodec.encode(Frame(
            requestID: 1, body: .appIcon(Self.icon))))
        data += try encoder.frame(FrameCodec.encode(Frame(requestID: 2, body: .hierarchy(hierarchy))))
        let ids = hierarchy.nodes.map(\.id).filter(holding)
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = LayerDetailsChunk(
                sequence: 0,
                details: ids[start..<min(start + chunkSize, ids.count)].compactMap { details[$0] })
            data += try encoder.frame(FrameCodec.encode(Frame(
                requestID: 3, body: .layerDetailsChunk(chunk))))
        }
        return data + encoder.trailer()
    }
}

/// What C-SCALE-01 is measured on, and how its results are reported: the 10,000 app-shaped
/// layers of `synthetic`, unless `CUTAWAY_SCALE_ARCHIVE` names an archive, whose replay is
/// then measured and only reported, since the limits are set for the synthetic scene
/// (C-MOCK-04).
public enum ScaleScene {
    public static let synthetic = SyntheticScene(
        layerCount: 10_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: true)

    /// The archive measured instead of the synthetic scene.
    public static var archivePath: String? {
        ProcessInfo.processInfo.environment["CUTAWAY_SCALE_ARCHIVE"]
    }

    /// Whether results are held to their limits: only for the synthetic scene. An archive's
    /// times are only reported. On a CI runner the timed tests do not run (`TestRunner`).
    public static var checksLimits: Bool { archivePath == nil }

    /// A responder for what is measured.
    public static func responder() throws -> MockResponder {
        guard let archivePath else { return synthetic.responder() }
        return try MockResponder(archive: archiveData(archivePath))
    }

    /// A server script for what is measured: the handshake, then `responder()`. With a
    /// gate, the first request for screenshots waits there, and every request after it with
    /// it, since a server answers in order: what is measured then does not share the main
    /// thread with screenshots arriving.
    public static func script(holdingDetailsAt gate: MockGate? = nil) throws -> MockScript {
        var responder = try responder()
        if let gate { responder.holdBeforeDetails = ({ _ in true }, gate) }
        var steps = try MockScript.fixtures("handshake").steps
        if let archivePath {
            steps = try MockScript.replaying(archive: archiveData(archivePath)).steps.dropLast()
        }
        return MockScript(steps: steps + [.respond(responder)])
    }

    public static func hierarchy() throws -> Hierarchy {
        guard let archivePath else { return synthetic.hierarchy() }
        return try ArchiveDecoder(archiveData(archivePath)).hierarchy
    }

    /// An archive of what is measured; for the synthetic scene with this interface state
    /// section, an archive's own being its own.
    public static func archive(state: Data = Data()) throws -> Data {
        guard let archivePath else { return try synthetic.archive(state: state) }
        return try archiveData(archivePath)
    }

    private static func archiveData(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
    }

    /// The median of `runs` measurements.
    public static func median(
        of runs: Int, _ measure: () throws -> Duration
    ) rethrows -> Duration {
        var times: [Duration] = []
        for _ in 0..<runs { times.append(try measure()) }
        return times.sorted()[times.count / 2]
    }

    public static func median(
        of runs: Int, isolation: isolated (any Actor)? = #isolation,
        _ measure: () async throws -> Duration
    ) async rethrows -> Duration {
        var times: [Duration] = []
        for _ in 0..<runs { times.append(try await measure()) }
        return times.sorted()[times.count / 2]
    }

    /// One line of the record C-SCALE-01 asks for, printed and returned for a failure message:
    /// `C-SCALE-01 search: 92.0 ms (limit 200 ms, 46%)`.
    @discardableResult
    public static func report(_ item: String, _ measured: Duration, limit: Duration) -> String {
        let share = Int((measured / limit * 100).rounded())
        let line = "C-SCALE-01 \(item): \(milliseconds(measured)) (limit \(milliseconds(limit)), \(share)%)"
            + (archivePath.map { " [\($0)]" } ?? "")
        print(line)
        return line
    }

    public static func milliseconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        return value >= 100 ? "\(Int(value.rounded())) ms" : String(format: "%.1f ms", value)
    }
}
