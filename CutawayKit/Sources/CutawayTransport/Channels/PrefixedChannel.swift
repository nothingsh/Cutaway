import Foundation

/// A channel that first hands out bytes that were read ahead of it.
actor PrefixedChannel: ByteChannel {
    private var prefix: Data?
    private let base: any ByteChannel

    init(prefix: Data, base: any ByteChannel) {
        self.prefix = prefix
        self.base = base
    }

    func send(_ data: Data) async throws {
        try await base.send(data)
    }

    func receive() async throws -> Data? {
        if let prefix {
            self.prefix = nil
            return prefix
        }
        return try await base.receive()
    }

    nonisolated func close() {
        base.close()
    }
}
