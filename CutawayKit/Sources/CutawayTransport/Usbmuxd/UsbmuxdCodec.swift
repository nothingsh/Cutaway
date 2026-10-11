import Foundation

// The part of the usbmuxd protocol that Cutaway uses, from the protocol's public description:
// the names and numbers below are the reference for the format.

/// What a client sends to usbmuxd.
package enum UsbmuxdRequest: Equatable, Sendable {
    case listen
    case connect(deviceID: Int, port: UInt16)
}

/// What usbmuxd sends to a client.
package enum UsbmuxdIncoming: Equatable, Sendable {
    /// The answer to a request. 0 is success.
    case result(Int)
    case attached(deviceID: Int, serial: String, connectionType: String)
    case detached(deviceID: Int)
    /// A message type this client has no use for.
    case other(String)
}

package struct UsbmuxdPacket: Equatable, Sendable {
    package var tag: UInt32
    /// The property list, without the header.
    package var payload: Data
}

package enum UsbmuxdError: Error, Equatable {
    /// Bytes that are not a usbmuxd message. The text is for logs.
    case malformed(String)
    /// usbmuxd answered a request with this non-zero result.
    case refused(Int)
    /// The connection to usbmuxd ended.
    case closed
}

package enum UsbmuxdCodec {
    package static let headerLength = 16
    /// Far above any message this client exchanges; guards against a bogus length.
    package static let maximumLength = 1 << 20
    static let version: UInt32 = 1
    /// The payload is a property list.
    static let plistType: UInt32 = 8

    package static func encode(_ request: UsbmuxdRequest, tag: UInt32) -> Data {
        var dictionary: [String: Any] = [
            "ClientVersionString": "cutaway",
            "ProgName": "Cutaway",
        ]
        switch request {
        case .listen:
            dictionary["MessageType"] = "Listen"
        case .connect(let deviceID, let port):
            dictionary["MessageType"] = "Connect"
            dictionary["DeviceID"] = deviceID
            // The port in network byte order, read back as a host-order integer.
            dictionary["PortNumber"] = Int(port.bigEndian)
        }
        return packet(dictionary, tag: tag)
    }

    package static func encode(_ incoming: UsbmuxdIncoming, tag: UInt32) -> Data {
        let dictionary: [String: Any]
        switch incoming {
        case .result(let number):
            dictionary = ["MessageType": "Result", "Number": number]
        case .attached(let deviceID, let serial, let connectionType):
            dictionary = [
                "MessageType": "Attached",
                "DeviceID": deviceID,
                "Properties": [
                    "ConnectionType": connectionType,
                    "DeviceID": deviceID,
                    "SerialNumber": serial,
                ] as [String: Any],
            ]
        case .detached(let deviceID):
            dictionary = ["MessageType": "Detached", "DeviceID": deviceID]
        case .other(let type):
            dictionary = ["MessageType": type]
        }
        return packet(dictionary, tag: tag)
    }

    package static func decodeRequest(_ payload: Data) throws -> UsbmuxdRequest {
        let dictionary = try self.dictionary(payload)
        switch dictionary["MessageType"] as? String {
        case "Listen":
            return .listen
        case "Connect":
            guard let deviceID = dictionary["DeviceID"] as? Int,
                  let number = dictionary["PortNumber"] as? Int,
                  let swapped = UInt16(exactly: number)
            else { throw UsbmuxdError.malformed("a Connect without DeviceID or PortNumber") }
            return .connect(deviceID: deviceID, port: UInt16(bigEndian: swapped))
        case let type:
            throw UsbmuxdError.malformed("unsupported request \(type ?? "without MessageType")")
        }
    }

    package static func decodeIncoming(_ payload: Data) throws -> UsbmuxdIncoming {
        let dictionary = try self.dictionary(payload)
        guard let type = dictionary["MessageType"] as? String else {
            throw UsbmuxdError.malformed("a message without MessageType")
        }
        switch type {
        case "Result":
            guard let number = dictionary["Number"] as? Int else {
                throw UsbmuxdError.malformed("a Result without Number")
            }
            return .result(number)
        case "Attached":
            guard let deviceID = dictionary["DeviceID"] as? Int,
                  let properties = dictionary["Properties"] as? [String: Any],
                  let serial = properties["SerialNumber"] as? String,
                  let connectionType = properties["ConnectionType"] as? String
            else { throw UsbmuxdError.malformed("an Attached without its properties") }
            return .attached(deviceID: deviceID, serial: serial, connectionType: connectionType)
        case "Detached":
            guard let deviceID = dictionary["DeviceID"] as? Int else {
                throw UsbmuxdError.malformed("a Detached without DeviceID")
            }
            return .detached(deviceID: deviceID)
        default:
            return .other(type)
        }
    }

    /// A whole message: the header and `dictionary` as an XML property list. Tests use it to
    /// build messages that `encode` cannot.
    package static func packet(_ dictionary: [String: Any], tag: UInt32) -> Data {
        guard
            let payload = try? PropertyListSerialization.data(
                fromPropertyList: dictionary, format: .xml, options: 0)
        else { preconditionFailure("a dictionary of strings and integers always serialises") }

        var packet = Data(capacity: headerLength + payload.count)
        for field in [UInt32(headerLength + payload.count), version, plistType, tag] {
            withUnsafeBytes(of: field.littleEndian) { packet.append(contentsOf: $0) }
        }
        packet.append(payload)
        return packet
    }

    private static func dictionary(_ payload: Data) throws -> [String: Any] {
        guard
            let dictionary = (try? PropertyListSerialization.propertyList(from: payload, format: nil))
            as? [String: Any]
        else { throw UsbmuxdError.malformed("the payload is not a property list dictionary") }
        return dictionary
    }

    /// The little-endian 32-bit field at `offset` in `data`.
    static func field(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * UInt32($1)) }
    }
}

/// Cuts usbmuxd messages out of a byte stream.
package struct UsbmuxdPacketReader: Sendable {
    private var buffer = Data()

    package init() {}

    package mutating func append(_ bytes: Data) {
        buffer.append(bytes)
    }

    /// The next complete message, or nil when more bytes are needed.
    package mutating func next() throws -> UsbmuxdPacket? {
        guard buffer.count >= UsbmuxdCodec.headerLength else { return nil }
        let length = Int(UsbmuxdCodec.field(buffer, at: 0))
        guard length >= UsbmuxdCodec.headerLength, length <= UsbmuxdCodec.maximumLength else {
            throw UsbmuxdError.malformed("a message length of \(length)")
        }
        guard UsbmuxdCodec.field(buffer, at: 4) == UsbmuxdCodec.version,
              UsbmuxdCodec.field(buffer, at: 8) == UsbmuxdCodec.plistType
        else { throw UsbmuxdError.malformed("a message that is not a version 1 property list") }
        guard buffer.count >= length else { return nil }

        let tag = UsbmuxdCodec.field(buffer, at: 12)
        let start = buffer.startIndex
        let payload = Data(buffer[(start + UsbmuxdCodec.headerLength)..<(start + length)])
        buffer = Data(buffer[(start + length)...])
        return UsbmuxdPacket(tag: tag, payload: payload)
    }

    /// Removes and returns the bytes that follow the last message taken. After a successful
    /// Connect they belong to the device, not to usbmuxd.
    package mutating func takeRemainder() -> Data {
        defer { buffer = Data() }
        return buffer
    }
}
