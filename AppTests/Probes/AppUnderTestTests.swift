import AppKit
import CutawayTransport
import XCTest

@testable import Cutaway

/// Test runs must not reach for real devices: connections to real devices and real servers
/// are tested by a person, not by the suite.
final class AppUnderTestTests: XCTestCase {
    @MainActor
    func test_C_MOCK_01_theAppUnderTestDoesNotDiscoverDevices() throws {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        XCTAssertFalse(delegate.discoversDevices)
    }

    /// A Cutaway or a server-side app left open would otherwise connect to the tests'
    /// MockServer, or be listed by the app under test (C-CONN-09).
    @MainActor
    func test_C_MOCK_01_theAppUnderTestScansNoneOfTheProtocolsPorts() throws {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        XCTAssertEqual(delegate.simulatorPorts.count, DiscoveryConfiguration.ports.count)
        XCTAssertTrue(Set(delegate.simulatorPorts).isDisjoint(with: DiscoveryConfiguration.ports))
    }
}
