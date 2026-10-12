import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Changing attributes (C-ATTR-04 to C-ATTR-08), at the level of the model: whether the
/// panel may edit, what is sent and when, what the answers do, and undo.
final class AttributeEditingTests: XCTestCase {
    private static let blue = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    private static func key(_ layer: UInt64, _ id: String) -> AttributeKey {
        AttributeKey(layerID: layer, attributeID: id)
    }

    /// The value an attribute has in some groups.
    private static func value(_ id: String, in groups: [AttributeGroup]) -> AttributeValue?? {
        for group in groups {
            if let attribute = group.attributes.first(where: { $0.id == id }) {
                return .some(attribute.value)
            }
        }
        return nil
    }

    /// The groups with one attribute's value replaced.
    private static func replacing(
        _ id: String, with value: AttributeValue?, in groups: [AttributeGroup]
    ) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == id { attribute.value = value }
                return attribute
            }
            return group
        }
    }

    /// A `SetAttribute` answered with these groups for that layer.
    private static func resultSteps(
        _ layer: UInt64, _ groups: [AttributeGroup], as requestID: UInt32
    ) -> [MockScript.Step] {
        [
            .expect(.setAttribute, as: requestID),
            .send(Frame(requestID: requestID, body: .setAttributeResult(SetAttributeResult(
                layerID: layer, attributeGroups: groups)))),
        ]
    }

    private static func errorSteps(_ code: ErrorCode, as requestID: UInt32) -> [MockScript.Step] {
        [
            .expect(.setAttribute, as: requestID),
            .send(Frame(requestID: requestID, body: .error(ServerError(code: code, message: nil)))),
        ]
    }

    /// The `SetAttribute` requests the server received, in order.
    private static func sets(_ server: MockServer) async -> [SetAttribute] {
        await server.receivedFrames.compactMap { frame in
            guard case .setAttribute(let request) = frame.body else { return nil }
            return request
        }
    }

    /// handshake and layer 3's attributes, then `steps`.
    private static func script(_ steps: [MockScript.Step]) throws -> MockScript {
        MockScript(steps: try MockScript.fixtures("handshake", "layer-details").steps + steps)
    }

    /// An open model that can edit, with layer 3 selected and its attributes loaded.
    @MainActor
    private func editing(
        _ script: MockScript, requestTimeout: Duration = .seconds(10),
        undoActionName: @escaping @Sendable (String) -> String = { $0 }
    ) async throws -> (AttributesStore, Session, MockServer) {
        let server = try await MockServer.start(script: script)
        let session = try await AttributesStoreTests.session(
            to: server, requestTimeout: requestTimeout)
        let model = AttributesStore(session: session, undoActionName: undoActionName)
        model.setOpen(true)
        model.setEditingSupported(true)
        model.select(3)
        let expected = try AttributesStoreTests.layerThree()
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        return (model, session, server)
    }

    // MARK: - C-ATTR-04

    func test_C_ATTR_04_onlyWhatTheServerMarksAndTheClientCanWriteIsEditable() throws {
        let attributes = try AttributesStoreTests.layerThree().flatMap(\.attributes)
        XCTAssertEqual(
            attributes.filter { !$0.isEditable }.map(\.id), ["layer.frame"],
            "layer-details: everything of layer 3 but its frame")

        let opacity = Attribute(
            id: "a", title: "A", value: .double(1), editable: true, valueKind: .double)
        XCTAssertTrue(opacity.isEditable)
        var unknownKind = opacity
        unknownKind.valueKind = .none
        XCTAssertFalse(unknownKind.isEditable, "a kind this client does not know")
        var mismatched = opacity
        mismatched.valueKind = .string
        XCTAssertFalse(mismatched.isEditable, "the value is not of its kind (P-ATTR-06)")
        var notMarked = opacity
        notMarked.editable = false
        XCTAssertFalse(notMarked.isEditable)
        let nilColor = Attribute(
            id: "c", title: "C", value: nil, editable: true, acceptsNil: true, valueKind: .color)
        XCTAssertTrue(nilColor.isEditable, "nil, with its kind given")

        func enumeration(_ caseValues: [Int64]) -> Attribute {
            Attribute(
                id: "e", title: "E",
                value: .enumeration(EnumValue(
                    value: 0, cases: ["a", "b"], caseName: "a", caseValues: caseValues)),
                editable: true, valueKind: .enumeration)
        }
        XCTAssertTrue(enumeration([0, 1]).isEditable)
        XCTAssertFalse(enumeration([]).isEditable, "no raw values (P-ATTR-07)")
        XCTAssertFalse(enumeration([0]).isEditable, "fewer raw values than cases")
    }

    @MainActor
    func test_C_ATTR_04_editingNeedsProtocol03AndAnActiveApp() async throws {
        let (model, session, server) = try await editing(try Self.script([]))
        XCTAssertTrue(model.canEdit)

        model.appStateDidChange(.background)
        XCTAssertFalse(model.canEdit, "not while the app is not active (P-APP-01)")
        model.set(Self.key(3, "label.text"), to: .string("Hi"), continuous: false)
        XCTAssertEqual(model.edits, [:], "nothing is sent")
        model.appStateDidChange(.active)
        XCTAssertTrue(model.canEdit)

        model.setEditingSupported(false)
        XCTAssertFalse(model.canEdit, "a server below 0.3 (P-HELLO-04)")
        model.set(Self.key(3, "label.text"), to: .string("Hi"), continuous: false)
        try await Task.sleep(for: .milliseconds(100))
        let sets = await Self.sets(server)
        XCTAssertEqual(sets, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_04_anInspectionLearnsWhetherTheServerCanBeEdited() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await AttributesStoreTests.session(to: server)
        let inspection = InspectionStore(session: session)
        XCTAssertFalse(inspection.attributes.canEdit)
        inspection.enter()
        let told = await Wait.until { await inspection.attributes.canEdit }
        XCTAssertTrue(told, "the fixture's server speaks 0.3")

        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-06

    @MainActor
    func test_C_ATTR_06_theAnswerReplacesTheLayersAttributes() async throws {
        let results = try Fixtures.setAttributeResults()
        let fixture = try MockScript.fixtures("set-attribute").steps
        // Layer 4's attributes, asked for when it is selected, sit between the scenario's
        // second and third request.
        var steps = Array(fixture.prefix(4))
        steps += MockScript.layerDetailsSteps(
            [LayerDetail(
                layerID: 4, status: .ok, solo: nil, group: nil,
                attributeGroups: try Fixtures.layerFourBeforeEditing())],
            as: 60)
        steps += fixture.dropFirst(4)
        let (model, session, server) = try await editing(try Self.script(steps))

        // Layer 3: the text, then the alignment by its raw value only (P-SET-02).
        model.set(Self.key(3, "label.text"), to: .string("Welcome back"), continuous: false)
        XCTAssertEqual(model.edits[Self.key(3, "label.text")], .sending(.string("Welcome back")))
        var answered = await Wait.until { await model.state == .loaded(results[0].attributeGroups) }
        XCTAssertTrue(answered)
        XCTAssertEqual(model.edits, [:])
        model.set(
            Self.key(3, "label.textAlignment"),
            to: .enumeration(EnumValue(value: 2, cases: [], caseName: nil)), continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[1].attributeGroups) }
        XCTAssertTrue(answered)

        // Layer 4: a colour where there was none, the alpha (which moves the opacity too),
        // and the colour back to nil.
        model.select(4)
        let loaded = await Wait.until {
            await model.state == .loaded(try! Fixtures.layerFourBeforeEditing())
        }
        XCTAssertTrue(loaded)
        model.set(Self.key(4, "layer.backgroundColor"), to: .color(Self.blue), continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[2].attributeGroups) }
        XCTAssertTrue(answered)
        model.set(Self.key(4, "view.alpha"), to: .double(0.5), continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[3].attributeGroups) }
        XCTAssertTrue(answered)
        if case .loaded(let groups, _) = model.state {
            XCTAssertEqual(Self.value("layer.opacity", in: groups), .some(.double(0.5)))
        }
        model.set(Self.key(4, "layer.backgroundColor"), to: nil, continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[4].attributeGroups) }
        XCTAssertTrue(answered)

        let sent = await Self.sets(server)
        XCTAssertEqual(sent.count, 5)
        XCTAssertNil(sent[4].value, "nil goes as no value")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_06_rejectionsShowInTheRowAndTheValueStays() async throws {
        let (model, session, server) = try await editing(
            try Self.script(Array(try MockScript.fixtures("set-attribute-rejected").steps.dropFirst(2))
                + Self.errorSteps(.appNotActive, as: 30)
                + [.expect(.setAttribute, as: 31)]),
            requestTimeout: .milliseconds(300))
        let before = model.state

        let frame = Self.key(3, "layer.frame")
        model.set(frame, to: .rect(.zero), continuous: false)
        var failed = await Wait.until { await model.edits[frame] == .failed(.notEditable) }
        XCTAssertTrue(failed)
        let opacity = Self.key(3, "layer.opacity")
        model.set(opacity, to: .string("half"), continuous: false)
        failed = await Wait.until { await model.edits[opacity] == .failed(.rejected) }
        XCTAssertTrue(failed)
        let lines = Self.key(3, "label.numberOfLines")
        model.set(lines, to: nil, continuous: false)
        failed = await Wait.until { await model.edits[lines] == .failed(.rejected) }
        XCTAssertTrue(failed)
        let text = Self.key(3, "label.text")
        model.set(text, to: .string("Hi"), continuous: false)
        failed = await Wait.until { await model.edits[text] == .failed(.appNotActive) }
        XCTAssertTrue(failed)
        let hidden = Self.key(3, "layer.hidden")
        model.set(hidden, to: .bool(true), continuous: false)
        failed = await Wait.until { await model.edits[hidden] == .failed(.noAnswer) }
        XCTAssertTrue(failed, "no answer in time")

        // The values the panel shows are the ones from before (P-SET-03: nothing changed).
        XCTAssertEqual(model.state, before)

        // The next change of an attribute clears its failure; another selection clears all.
        model.set(frame, to: .rect(.zero), continuous: false)
        XCTAssertEqual(model.edits[frame], .sending(.rect(.zero)))
        model.select(nil)
        XCTAssertNil(model.edits[opacity])
        XCTAssertNil(model.edits[lines])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_06_aLayerThatIsGoneSaysSoForThePanel() async throws {
        let (model, session, server) = try await editing(
            try Self.script(Self.errorSteps(.layerNotFound, as: 30)))
        model.set(Self.key(3, "label.text"), to: .string("Hi"), continuous: false)
        let gone = await Wait.until { await model.state == .layerGone }
        XCTAssertTrue(gone)
        XCTAssertEqual(model.edits, [:])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_06_anAnswerForALayerNoLongerSelectedKeepsItsCacheOnly() async throws {
        let gate = MockGate()
        let groups = Self.replacing(
            "label.text", with: .string("Later"), in: try AttributesStoreTests.layerThree())
        var steps = Self.resultSteps(3, groups, as: 30)
        steps.insert(.hold(gate), at: 1)
        let (model, session, server) = try await editing(try Self.script(steps))

        model.set(Self.key(3, "label.text"), to: .string("Later"), continuous: false)
        let sent = await Wait.until { await Self.sets(server).count == 1 }
        XCTAssertTrue(sent)
        model.select(nil)
        await gate.open()
        let settled = await Wait.until { await model.edits.isEmpty }
        XCTAssertTrue(settled)
        XCTAssertEqual(model.state, .none)
        // Selected again, layer 3 shows the answer without asking.
        model.select(3)
        XCTAssertEqual(model.state, .loaded(groups))

        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-07

    @MainActor
    func test_C_ATTR_07_whileOneIsOnItsWayOnlyTheLatestValueWaits() async throws {
        let gate = MockGate()
        let layerThree = try AttributesStoreTests.layerThree()
        var steps = Self.resultSteps(
            3, Self.replacing("layer.opacity", with: .double(0.99), in: layerThree), as: 30)
        steps.insert(.hold(gate), at: 1)
        steps += Self.resultSteps(
            3, Self.replacing("layer.opacity", with: .double(0.5), in: layerThree), as: 31)
        let (model, session, server) = try await editing(try Self.script(steps))
        let opacity = Self.key(3, "layer.opacity")

        model.set(opacity, to: .double(0.99), continuous: true)
        let first = await Wait.until { await Self.sets(server).count == 1 }
        XCTAssertTrue(first)
        // 100 values before the answer comes: the last one ends the drag.
        for step in 1...100 {
            model.set(
                opacity, to: .double(0.99 - Double(step) * 0.0049), continuous: step < 100)
        }
        XCTAssertEqual(model.edits[opacity], .sending(.double(0.99 - 100 * 0.0049)))
        await gate.open()
        let settled = await Wait.until { await model.edits.isEmpty }
        XCTAssertTrue(settled)
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [.double(0.99), .double(0.99 - 100 * 0.0049)])
        // What the app read back is shown (P-SET-04).
        if case .loaded(let groups, _) = model.state {
            XCTAssertEqual(Self.value("layer.opacity", in: groups), .some(.double(0.5)))
        } else {
            XCTFail("\(model.state)")
        }

        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-08

    @MainActor
    func test_C_ATTR_08_aChangeCanBeUndoneAndRedone() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let changed = Self.replacing("label.text", with: .string("Bye"), in: layerThree)
        let steps = Self.resultSteps(3, changed, as: 30) + Self.resultSteps(3, layerThree, as: 31)
            + Self.resultSteps(3, changed, as: 32)
        let (model, session, server) = try await editing(try Self.script(steps))
        let undo = model.undoManager
        XCTAssertFalse(undo.canUndo)

        model.set(Self.key(3, "label.text"), to: .string("Bye"), continuous: false)
        var done = await Wait.until { await model.state == .loaded(changed) }
        XCTAssertTrue(done)
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Text", "the interface words it (C-LOC-01)")

        undo.undo()
        done = await Wait.until { await model.state == .loaded(layerThree) }
        XCTAssertTrue(done, "the value from before was sent")
        XCTAssertTrue(undo.canRedo)
        XCTAssertFalse(undo.canUndo)

        undo.redo()
        done = await Wait.until { await model.state == .loaded(changed) }
        XCTAssertTrue(done)
        XCTAssertTrue(undo.canUndo)
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [.string("Bye"), .string("Hello"), .string("Bye")])

        // Leaving the inspection empties the stack.
        model.setOpen(false)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.canRedo)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_08_aDragIsOneStepAndFailuresAreNotRecorded() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let steps = Self.resultSteps(
            3, Self.replacing("layer.opacity", with: .double(0.8), in: layerThree), as: 30)
            + Self.resultSteps(
                3, Self.replacing("layer.opacity", with: .double(0.6), in: layerThree), as: 31)
            + Self.errorSteps(.invalidAttributeValue, as: 32)
            + Self.resultSteps(3, layerThree, as: 33)
        let (model, session, server) = try await editing(try Self.script(steps))
        let opacity = Self.key(3, "layer.opacity")
        let undo = model.undoManager

        model.set(opacity, to: .double(0.8), continuous: true)
        let first = await Wait.until {
            await model.state == .loaded(
                Self.replacing("layer.opacity", with: .double(0.8), in: layerThree))
        }
        XCTAssertTrue(first, "the drag's first value was answered")
        XCTAssertEqual(model.edits[opacity], .sending(.double(0.8)), "the drag goes on")
        XCTAssertFalse(undo.canUndo, "the drag goes on")
        model.set(opacity, to: .double(0.6), continuous: false)
        var settled = await Wait.until { await model.edits.isEmpty }
        XCTAssertTrue(settled)
        XCTAssertTrue(undo.canUndo)

        // A rejected change adds nothing.
        model.set(Self.key(3, "label.text"), to: .string("x"), continuous: false)
        let failed = await Wait.until {
            await model.edits[Self.key(3, "label.text")] == .failed(.rejected)
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(undo.undoActionName, "Opacity")

        // One undo takes the whole drag back, to the value before it.
        undo.undo()
        settled = await Wait.until { await model.state == .loaded(layerThree) }
        XCTAssertTrue(settled)
        XCTAssertFalse(undo.canUndo)
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.last?.value, .double(1))

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_08_undoingALayerThatIsGoneDropsTheStep() async throws {
        let changed = Self.replacing(
            "label.text", with: .string("Bye"), in: try AttributesStoreTests.layerThree())
        let steps = Self.resultSteps(3, changed, as: 30) + Self.errorSteps(.layerNotFound, as: 31)
        let (model, session, server) = try await editing(try Self.script(steps))
        let undo = model.undoManager

        model.set(Self.key(3, "label.text"), to: .string("Bye"), continuous: false)
        let done = await Wait.until { await model.state == .loaded(changed) }
        XCTAssertTrue(done)
        undo.undo()
        let gone = await Wait.until { await model.state == .layerGone }
        XCTAssertTrue(gone)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.canRedo, "the step is gone, not waiting to be redone")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_08_aDragEndedWithoutANewValueIsOneStep() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let blue = Self.replacing("layer.borderColor", with: .color(Self.blue), in: layerThree)
        // The name the interface gives a change (C-LOC-01).
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, blue, as: 30)), undoActionName: { "Change \($0)" })
        let border = Self.key(3, "layer.borderColor")

        // The color panel's last value, then a pause: no new value is sent for the end.
        model.set(border, to: .color(Self.blue), continuous: true)
        let answered = await Wait.until { await model.state == .loaded(blue) }
        XCTAssertTrue(answered)
        XCTAssertFalse(model.undoManager.canUndo)
        model.finish(border)
        XCTAssertEqual(model.edits, [:])
        XCTAssertTrue(model.undoManager.canUndo)
        XCTAssertEqual(model.undoManager.undoActionName, "Change Border Color")
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.count, 1)

        await session.close()
        await server.stop()
    }

    /// Found while testing the panel: when the answer came, the row stopped sending before the
    /// new attributes were out, and showed the old value for a moment.
    @MainActor
    func test_C_ATTR_06_aRowStopsSendingOnlyOnceTheAnswerIsOut() async throws {
        let changed = Self.replacing(
            "label.text", with: .string("Bye"), in: try AttributesStoreTests.layerThree())
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, changed, as: 30)))
        let key = Self.key(3, "label.text")
        var statesWhenCleared: [AttributesStore.State] = []
        // `edits` sends before it changes; `state` is read as it is at that moment.
        let watch = model.$edits.sink { edits in
            if edits[key] == nil { statesWhenCleared.append(model.state) }
        }
        model.set(key, to: .string("Bye"), continuous: false)
        let done = await Wait.until {
            await MainActor.run { model.edits.isEmpty && model.state == .loaded(changed) }
        }
        XCTAssertTrue(done)
        watch.cancel()
        // The first value is the subscription's own, before the change.
        XCTAssertEqual(statesWhenCleared.dropFirst(), [.loaded(changed)])

        await session.close()
        await server.stop()
    }

    // MARK: - Found in review

    /// A drag whose end was dropped (editing stopped) stayed "sending" for good, with no undo.
    @MainActor
    func test_C_ATTR_07_aDragCutShortByTheAppStillEnds() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let dragged = Self.replacing("layer.opacity", with: .double(0.8), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "layer.opacity")
        model.set(opacity, to: .double(0.8), continuous: true)
        let answered = await Wait.until { await model.state == .loaded(dragged) }
        XCTAssertTrue(answered)

        model.appStateDidChange(.background)
        model.set(opacity, to: .double(0.7), continuous: false)
        XCTAssertEqual(model.edits, [:])
        XCTAssertTrue(model.undoManager.canUndo, "the drag up to 0.8 is one step")
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.count, 1, "nothing is sent while editing is off")

        await session.close()
        await server.stop()
    }

    /// An editor left over from the layer selected before (a color well still attached to the
    /// color panel) cannot change that layer: only the selected layer's attributes are set.
    @MainActor
    func test_C_ATTR_06_aChangeForALayerNoLongerSelectedIsNotSent() async throws {
        let (model, session, server) = try await editing(try Self.script([]))
        model.select(nil)
        let text = Self.key(3, "label.text")
        model.set(text, to: .string("Stale"), continuous: true)
        model.set(text, to: .string("Stale"), continuous: false)
        model.finish(text)
        XCTAssertEqual(model.edits, [:])
        XCTAssertFalse(model.undoManager.canUndo)
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.count, 0, "nothing is sent for a layer no longer selected")

        await session.close()
        await server.stop()
    }

    /// A drag whose layer is no longer selected ended with the selection; the values its
    /// editor still sends go nowhere, and the drag stays the one step it made.
    @MainActor
    func test_C_ATTR_07_aDragGoingOnAfterAnotherSelectionSendsNothingMore() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let dragged = Self.replacing("layer.opacity", with: .double(0.8), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "layer.opacity")
        model.set(opacity, to: .double(0.8), continuous: true)
        let answered = await Wait.until { await model.state == .loaded(dragged) }
        XCTAssertTrue(answered)

        model.select(nil)
        model.set(opacity, to: .double(0.6), continuous: true)
        model.set(opacity, to: .double(0.5), continuous: false)
        XCTAssertEqual(model.edits, [:])
        XCTAssertTrue(model.undoManager.canUndo, "the drag up to 0.8 is one step")
        // A stale value would have gone right after the answer it waited for.
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [.double(0.8)], "only the value before the selection moved")

        await session.close()
        await server.stop()
    }
}
