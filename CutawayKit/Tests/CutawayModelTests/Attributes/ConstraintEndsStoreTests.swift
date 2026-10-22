import Combine
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The other ends of the selected layer's constraints, which the preview marks (C-LAYOUT-04,
/// C-LAYOUT-07).
final class ConstraintEndsStoreTests: XCTestCase {
    /// The safe area of layer 2 in the `layout-constraints` fixture.
    private static let safeArea = SceneRect(x: 0, y: 59, width: 393, height: 759)

    private static func safeAreaGuide() throws -> LayoutGuide {
        guard case .layoutGuide(let guide)? = try Fixtures.constraints(of: 3)[1].secondItem else {
            throw XCTSkip("the fixture changed shape")
        }
        return guide
    }

    private static func constraint(
        _ first: LayoutItem?, _ second: LayoutItem?, id: UInt64 = 1
    ) -> LayoutConstraint {
        LayoutConstraint(
            id: id, className: "NSLayoutConstraint", identifier: nil, firstItem: first,
            firstAttribute: .top, relation: .equal, secondItem: second,
            secondAttribute: second == nil ? .notAnAttribute : .top, multiplier: 1, constant: 0,
            priority: 1000, status: .satisfied)
    }

    private static func guide(owner: UInt64, id: UInt64, frame: Rect?) -> LayoutGuide {
        LayoutGuide(
            ownerLayerID: owner, guideID: id, className: "UILayoutGuide",
            displayClassName: "UILayoutGuide", identifier: nil, frame: frame)
    }

    // MARK: - Which ends

    func test_C_LAYOUT_04_layer3sEndsAreLayer2ItsSafeAreaAndLayer4() throws {
        let ends = ConstraintEnd.ends(of: try Fixtures.constraints(of: 3), selected: 3)
        XCTAssertEqual(
            ends,
            [
                ConstraintEnd(mark: .layer(2)),
                ConstraintEnd(mark: .area(Self.safeArea, in: 2), guide: try Self.safeAreaGuide()),
                ConstraintEnd(mark: .layer(4)),
            ])
    }

    func test_C_LAYOUT_04_layer4sEndsAreLayer3AndLayer2() throws {
        let ends = ConstraintEnd.ends(of: try Fixtures.constraints(of: 4), selected: 4)
        XCTAssertEqual(ends, [ConstraintEnd(mark: .layer(3)), ConstraintEnd(mark: .layer(2))])
    }

    func test_C_LAYOUT_04_theUIKitConstraintsCountAndAnEndIsMarkedOnce() throws {
        let constraints = try Fixtures.constraints(of: 9)
        XCTAssertEqual(constraints.count, 4)
        XCTAssertEqual(
            ConstraintEnd.ends(of: constraints, selected: 9), [ConstraintEnd(mark: .layer(2))])
    }

    func test_C_LAYOUT_04_endsThatAreNotAViewOrAGuideWithAFiniteFrameAreNotMarked() {
        let unplaced = Self.guide(owner: 2, id: 5, frame: nil)
        let infinite = Self.guide(
            owner: 2, id: 6,
            frame: Rect(origin: Point(x: 0, y: .nan), size: Size(width: .infinity, height: 1)))
        let constraints = [
            Self.constraint(.view(layerID: 3), .layoutGuide(infinite)),
            Self.constraint(.view(layerID: 3), .other(className: "NSObject", displayClassName: nil)),
            Self.constraint(.view(layerID: 3), .layoutGuide(unplaced)),
            Self.constraint(nil, .view(layerID: 3)),
            Self.constraint(.view(layerID: 3), nil),
        ]
        XCTAssertEqual(ConstraintEnd.ends(of: constraints, selected: 3), [])
    }

    /// P-LAYOUT-08: the ends are marked whatever their attributes.
    func test_C_LAYOUT_05_anEndWithAnUnknownAttributeIsMarked() {
        var constraint = Self.constraint(.view(layerID: 3), .view(layerID: 4))
        constraint.firstAttribute = .notAnAttribute
        constraint.secondAttribute = .notAnAttribute
        XCTAssertEqual(
            ConstraintEnd.ends(of: [constraint], selected: 3), [ConstraintEnd(mark: .layer(4))])
    }

    func test_C_LAYOUT_04_eitherItemCanBeTheOtherEnd() {
        let constraints = [
            Self.constraint(.view(layerID: 7), .view(layerID: 3)),
            Self.constraint(.view(layerID: 3), .view(layerID: 8)),
        ]
        XCTAssertEqual(
            ConstraintEnd.ends(of: constraints, selected: 3),
            [ConstraintEnd(mark: .layer(7)), ConstraintEnd(mark: .layer(8))])
    }

    func test_C_LAYOUT_04_aGuideOfTheSelectedViewIsMarkedAndBothEndsCanBeOthers() {
        let own = Self.guide(
            owner: 3, id: 1, frame: Rect(origin: Point(x: 0, y: 2), size: Size(width: 10, height: 4)))
        let constraints = [
            Self.constraint(.view(layerID: 3), .layoutGuide(own)),
            // Refers to the selected view only through its guide.
            Self.constraint(.view(layerID: 4), .layoutGuide(own)),
        ]
        XCTAssertEqual(
            ConstraintEnd.ends(of: constraints, selected: 3),
            [
                ConstraintEnd(mark: .area(SceneRect(x: 0, y: 2, width: 10, height: 4), in: 3), guide: own),
                ConstraintEnd(mark: .layer(4)),
            ])
    }

    func test_C_LAYOUT_04_twoGuidesOfOneOwnerAreTwoEndsAndAGuideIsMarkedOnce() {
        let frame = Rect(origin: .zero, size: Size(width: 10, height: 10))
        let first = Self.guide(owner: 2, id: 1, frame: frame)
        let second = Self.guide(owner: 2, id: 2, frame: frame)
        let constraints = [
            Self.constraint(.view(layerID: 3), .layoutGuide(first)),
            Self.constraint(.view(layerID: 3), .layoutGuide(second)),
            Self.constraint(.layoutGuide(first), .view(layerID: 3)),
        ]
        XCTAssertEqual(
            ConstraintEnd.ends(of: constraints, selected: 3).map(\.guide), [first, second])
    }

    // MARK: - The inspection

    /// An inspection whose panel gets layers 3 and 4 (as requests 10 and 11), with the
    /// hierarchy loaded. Screenshots are held back.
    @MainActor
    private func openInspection() async throws -> (InspectionStore, Session, MockServer) {
        var steps = try MockScript.fixtures("handshake").steps
        steps += try MockScript.fixtures("hierarchy").steps
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 10)
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 4)], as: 11)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await AttributesStoreTests.session(to: server)
        let inspection = InspectionStore(session: session)
        inspection.rowsWait = .seconds(30)
        inspection.enter()
        let ready = await Wait.until {
            await MainActor.run { inspection.loadState == .loaded && inspection.attributes.canEdit }
        }
        XCTAssertTrue(ready)
        return (inspection, session, server)
    }

    @MainActor
    func test_C_LAYOUT_04_theInspectionGivesTheSelectedLayersEndsOnceItsConstraintsArrive()
        async throws
    {
        let (inspection, session, server) = try await openInspection()
        inspection.setShowsAllConstraintEnds(true)
        var published: [[ConstraintEnd]] = []
        let subscription = inspection.$constraintEnds.sink { published.append($0) }
        XCTAssertEqual(inspection.constraintEnds, [])

        inspection.select(3)
        let three = ConstraintEnd.ends(of: try Fixtures.constraints(of: 3), selected: 3)
        let gotThree = await Wait.until { await inspection.constraintEnds == three }
        XCTAssertTrue(gotThree, "\(inspection.constraintEnds)")

        inspection.select(4)
        let four = [ConstraintEnd(mark: .layer(3)), ConstraintEnd(mark: .layer(2))]
        let gotFour = await Wait.until { await inspection.constraintEnds == four }
        XCTAssertTrue(gotFour, "\(inspection.constraintEnds)")
        // Layer 3's ends go as soon as layer 4 is selected; they are not shown for layer 4.
        XCTAssertEqual(published, [[], three, [], four])

        subscription.cancel()
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_07_withTheSwitchOffOnlyThePointedRowsEndsAreMarked() async throws {
        let (inspection, session, server) = try await openInspection()
        inspection.select(3)
        let three = ConstraintEnd.ends(of: try Fixtures.constraints(of: 3), selected: 3)
        let loaded = await Wait.until {
            if case .loaded = await inspection.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(inspection.constraintEnds, [], "selecting marks nothing")

        inspection.pointConstraints([1], stresses: true)
        XCTAssertEqual(inspection.constraintEnds, [three[1]])
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [three[1].mark])

        // The next row is entered before the last one is left.
        inspection.pointConstraints([3], stresses: true)
        inspection.leaveConstraints([1])
        XCTAssertEqual(inspection.constraintEnds, [three[2]])
        inspection.leaveConstraints([3])
        XCTAssertEqual(inspection.constraintEnds, [])
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [])

        // The switch shows them all, the pointed one stressed.
        inspection.pointConstraints([1], stresses: true)
        inspection.toggleConstraintEnds()
        XCTAssertEqual(inspection.constraintEnds, three)
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [three[1].mark])
        inspection.toggleConstraintEnds()

        // Another layer forgets what was pointed at.
        inspection.select(4)
        let four = await Wait.until {
            if case .loaded = await inspection.attributes.state {
                return await inspection.attributes.selectedID == 4
            }
            return false
        }
        XCTAssertTrue(four)
        XCTAssertEqual(inspection.constraintEnds, [])
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_06_aChipShowsAndStressesItsEndWithTheSwitchOff() async throws {
        let (inspection, session, server) = try await openInspection()
        inspection.select(3)
        let loaded = await Wait.until {
            if case .loaded = await inspection.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        inspection.hoverConstraintEnd(.layer(4), layerID: 4)
        XCTAssertEqual(inspection.constraintEnds.map(\.mark), [.layer(4)])
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [.layer(4)])
        XCTAssertEqual(inspection.hoveredLayerID, 4)
        inspection.hoverConstraintEnd(nil, layerID: nil)
        XCTAssertEqual(inspection.constraintEnds, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_WIN_03_whatThePanelPointedAtIsNoLongerStressedOnceDisconnected() async throws {
        let (inspection, session, server) = try await openInspection()
        inspection.select(3)
        let loaded = await Wait.until {
            if case .loaded = await inspection.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        inspection.pointConstraints([1], stresses: true)
        inspection.hoverConstraintEnd(.layer(4), layerID: 4)
        XCTAssertFalse(inspection.emphasizedConstraintEnds.isEmpty)

        inspection.connectionLost()
        XCTAssertEqual(inspection.constraintEnds, [])
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [])
        // The switch still marks every end, none of them stressed.
        inspection.showsAllConstraintEnds = true
        inspection.showConstraintEnds()
        let three = ConstraintEnd.ends(of: try Fixtures.constraints(of: 3), selected: 3)
        XCTAssertEqual(inspection.constraintEnds, three)
        XCTAssertEqual(inspection.emphasizedConstraintEnds, [])

        await session.close()
        await server.stop()
    }
}
