import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-ATTR-09, at the level of the model: a value with a number that is not finite is never
/// sent; the row goes back to the value it had.
final class NonFiniteAttributeTests: XCTestCase {
    /// The value of the attribute's kind with one number spoiled, or nil for a kind without
    /// numbers that can be.
    private static func spoiled(_ kind: AttributeValueKind, with bad: Double) -> AttributeValue? {
        switch kind {
        case .double: .double(bad)
        case .point: .point(Point(x: 1, y: bad))
        case .size: .size(Size(width: bad, height: 2))
        case .rect: .rect(Rect(origin: Point(x: 0, y: 0), size: Size(width: 3, height: bad)))
        case .insets: .insets(Insets(top: 0, left: bad, bottom: 0, right: 0))
        case .transform:
            .transform(Transform3D(
                m11: 1, m12: 0, m13: 0, m14: 0, m21: 0, m22: 1, m23: 0, m24: 0,
                m31: 0, m32: 0, m33: 1, m34: bad, m41: 0, m42: 0, m43: 0, m44: 1))
        case .color: .color(Color(red: 0.5, green: Float(bad), blue: 0.5, alpha: 1))
        default: nil
        }
    }

    @MainActor
    func test_C_ATTR_09_aNonFiniteValueIsNeverSent() async throws {
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake", "layer-details").steps))
        let session = try await AttributesStoreTests.session(to: server)
        let model = AttributesStore(session: session)
        model.setOpen(true)
        model.setEditingSupported(true)
        model.select(3)
        let expected = try AttributesStoreTests.layerThree()
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)

        var tried: [AttributeValueKind] = []
        for attribute in expected.flatMap(\.attributes) where attribute.isEditable {
            for bad in [Double.nan, .infinity, -.infinity] {
                guard let id = attribute.id,
                      let value = Self.spoiled(attribute.valueKind, with: bad)
                else { continue }
                if !tried.contains(attribute.valueKind) { tried.append(attribute.valueKind) }
                let key = AttributeKey(layerID: 3, attributeID: id)
                for continuous in [false, true] {
                    model.set(key, to: value, continuous: continuous)
                    XCTAssertEqual(
                        model.edits[key], .failed(.notFinite), "\(id), \(value)")
                }
            }
        }
        for kind: AttributeValueKind in [.double, .point, .size, .insets, .color, .transform] {
            XCTAssertTrue(tried.contains(kind), "kinds tried: \(tried)")
        }

        // Give anything that was sent the time to arrive.
        try await Task.sleep(for: .milliseconds(200))
        let sets = await server.receivedFrames.filter {
            if case .setAttribute = $0.body { return true }
            return false
        }
        XCTAssertEqual(sets, [])
        await session.close()
    }

    @MainActor
    func test_C_ATTR_09_aDragThatReachesANonFiniteValueKeepsItsLastGoodOne() async throws {
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake", "layer-details").steps))
        let session = try await AttributesStoreTests.session(to: server)
        let model = AttributesStore(session: session)
        model.setOpen(true)
        model.setEditingSupported(true)
        model.select(3)
        let expected = try AttributesStoreTests.layerThree()
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        let attribute = try XCTUnwrap(
            expected.flatMap(\.attributes).first { $0.isEditable && $0.valueKind == .double })
        let key = AttributeKey(layerID: 3, attributeID: try XCTUnwrap(attribute.id))

        model.set(key, to: .double(0.25), continuous: true)
        model.set(key, to: .double(.infinity), continuous: true)
        model.set(key, to: .double(.nan), continuous: false)
        XCTAssertEqual(model.edits[key], .sending(.double(0.25)), "the drag's last good value")

        let sent = await Wait.until {
            await server.receivedFrames.contains {
                if case .setAttribute = $0.body { return true }
                return false
            }
        }
        XCTAssertTrue(sent)
        try await Task.sleep(for: .milliseconds(200))
        let values = await server.receivedFrames.compactMap { frame -> AttributeValue?? in
            guard case .setAttribute(let request) = frame.body else { return nil }
            return .some(request.value)
        }
        XCTAssertEqual(values, [.some(.double(0.25))])
        await session.close()
    }

    func test_C_ATTR_09_onlyValuesWhoseNumbersAreAllFiniteAreFinite() {
        XCTAssertTrue(AttributeValue.double(1e308).isFinite)
        XCTAssertTrue(AttributeValue.integer(.max).isFinite)
        XCTAssertTrue(AttributeValue.string("nan").isFinite)
        XCTAssertFalse(AttributeValue.double(.nan).isFinite)
        let kinds: [AttributeValueKind] = [
            .double, .point, .size, .rect, .insets, .transform, .color,
        ]
        for kind in kinds {
            for bad in [Double.nan, .infinity, -.infinity] {
                XCTAssertEqual(Self.spoiled(kind, with: bad)?.isFinite, false, "\(kind) \(bad)")
            }
            XCTAssertEqual(Self.spoiled(kind, with: 0.5)?.isFinite, true, "\(kind)")
        }
    }
}
