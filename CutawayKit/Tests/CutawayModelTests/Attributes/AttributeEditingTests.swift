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

    /// The app as a test's script plays it, except that a layer's details asked for again
    /// after a change of it succeeded (C-LAYOUT-01) are answered here, with the attributes the
    /// change returned and no constraints: the scripts are about the changes.
    private actor AnsweringAgain: InspectionSource {
        let session: Session
        private var changed: [UInt64: [AttributeGroup]] = [:]

        init(_ session: Session) {
            self.session = session
        }

        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { get async { await session.negotiatedVersion } }

        func hierarchy() async throws -> Hierarchy { try await session.hierarchy() }
        func subtree(of rootID: UInt64) async throws -> Hierarchy {
            try await session.subtree(of: rootID)
        }

        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            guard let asked = request.requests.first, request.requests.count == 1,
                  let groups = changed[asked.layerID]
            else { return await session.layerDetails(request) }
            let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
            continuation.yield([LayerDetail(
                layerID: asked.layerID, status: .ok, solo: nil, group: nil,
                attributeGroups: groups)])
            continuation.finish()
            return LayerDetailsStream(chunks: chunks, cancelAction: {})
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            let result = try await session.setAttribute(request)
            changed[result.layerID] = result.attributeGroups
            return result
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
        let model = AttributesStore(
            source: AnsweringAgain(session), undoActionName: undoActionName)
        model.setOpen(true)
        model.setEditingSupported(true)
        model.select(3)
        let expected = try AttributesStoreTests.layerThree()
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        return (model, session, server)
    }

    // MARK: - C-ATTR-04

    func test_C_WIRE_12_aReferenceIsNeverEditable() {
        let reference = Attribute(
            id: "scrollView.delegate", title: "Delegate",
            value: .references([ObjectReference(layerID: 2, className: "A", displayClassName: "A")]),
            editable: true, valueKind: .references)
        XCTAssertFalse(reference.isEditable, "P-ATTR-18: read-only even when marked editable")
        var empty = reference
        empty.value = .references([])
        XCTAssertFalse(empty.isEditable)
        XCTAssertNil(reference.value?.numericComponents)
    }

    func test_C_ATTR_04_onlyWhatTheServerMarksAndTheClientCanWriteIsEditable() throws {
        let attributes = try AttributesStoreTests.layerThree().flatMap(\.attributes)
        XCTAssertEqual(
            attributes.filter { !$0.isEditable }.map(\.id), ["layer.frame", "label.fontTextStyle"],
            "layer-details: everything of layer 3 but its frame and its text style")

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
    func test_C_ATTR_04_editingNeedsASourceThatTakesChangesAndAnActiveApp() async throws {
        let (model, session, server) = try await editing(try Self.script([]))
        XCTAssertTrue(model.canEdit)

        model.appStateDidChange(.background)
        XCTAssertFalse(model.canEdit, "not while the app is not active (P-APP-01)")
        model.set(Self.key(3, "label.text"), to: .string("Hi"), continuous: false)
        XCTAssertEqual(model.edits, [:], "nothing is sent")
        model.appStateDidChange(.active)
        XCTAssertTrue(model.canEdit)

        model.setEditingSupported(false)
        XCTAssertFalse(model.canEdit, "an archive (C-ARCH-05)")
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
        XCTAssertTrue(told, "an app can be changed")

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
        model.set(Self.key(4, "view.backgroundColor"), to: .color(Self.blue), continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[2].attributeGroups) }
        XCTAssertTrue(answered)
        model.set(Self.key(4, "view.alpha"), to: .double(0.5), continuous: false)
        answered = await Wait.until { await model.state == .loaded(results[3].attributeGroups) }
        XCTAssertTrue(answered)
        if case .loaded(let groups, _) = model.state {
            XCTAssertEqual(Self.value("view.alpha", in: groups), .some(.double(0.5)))
        }
        model.set(Self.key(4, "view.backgroundColor"), to: nil, continuous: false)
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

    /// An attribute of a group the host app adds is edited as any other (C-ATTR-23): its ID is
    /// sent as it is, and the answer replaces the layer's attributes.
    @MainActor
    func test_C_ATTR_23_anAppsAttributeIsEditedAsAnyOther() async throws {
        let before = try Fixtures.attributes(of: 10, scenario: "layer-details")
        let after = try XCTUnwrap(Fixtures.setAttributeResults().last { $0.layerID == 10 })
        var steps = MockScript.layerDetailsSteps(
            [LayerDetail(layerID: 10, status: .ok, solo: nil, group: nil, attributeGroups: before)],
            as: 60)
        steps += Self.resultSteps(10, after.attributeGroups, as: 61)
        let (model, session, server) = try await editing(try Self.script(steps))

        model.select(10)
        let loaded = await Wait.until { await model.state == .loaded(before) }
        XCTAssertTrue(loaded)
        model.set(Self.key(10, "app.row.title"), to: .string("Grand Total"), continuous: false)
        let answered = await Wait.until { await model.state == .loaded(after.attributeGroups) }
        XCTAssertTrue(answered)

        let sent = await Self.sets(server)
        XCTAssertEqual(
            sent, [SetAttribute(layerID: 10, attributeID: "app.row.title", value: .string("Grand Total"))])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_06_rejectionsShowInTheRowAndTheValueStays() async throws {
        let (model, session, server) = try await editing(
            // Without the two values outside the limits (1.1), which the client never sends
            // (P-SET-07), the layer's attributes of two pairs, which layer 3 does not have
            // (P-ATTR-11), and a view attribute on a virtual node (1.2, P-DET-09).
            try Self.script(Array(try MockScript.fixtures("set-attribute-rejected").steps.dropFirst(2).dropLast(10))
                + Self.errorSteps(.appNotActive, as: 30)
                + [.expect(.setAttribute, as: 31)]),
            requestTimeout: .milliseconds(300))
        let before = model.state

        let frame = Self.key(3, "layer.frame")
        model.set(frame, to: .rect(.zero), continuous: false)
        var failed = await Wait.until { await model.edits[frame] == .failed(.notEditable) }
        XCTAssertTrue(failed)
        let opacity = Self.key(3, "view.alpha")
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
        let hidden = Self.key(3, "view.isHidden")
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
            3, Self.replacing("view.alpha", with: .double(0.99), in: layerThree), as: 30)
        steps.insert(.hold(gate), at: 1)
        steps += Self.resultSteps(
            3, Self.replacing("view.alpha", with: .double(0.5), in: layerThree), as: 31)
        let (model, session, server) = try await editing(try Self.script(steps))
        let opacity = Self.key(3, "view.alpha")

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
            XCTAssertEqual(Self.value("view.alpha", in: groups), .some(.double(0.5)))
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
            3, Self.replacing("view.alpha", with: .double(0.8), in: layerThree), as: 30)
            + Self.resultSteps(
                3, Self.replacing("view.alpha", with: .double(0.6), in: layerThree), as: 31)
            + Self.errorSteps(.invalidAttributeValue, as: 32)
            + Self.resultSteps(3, layerThree, as: 33)
        let (model, session, server) = try await editing(try Self.script(steps))
        let opacity = Self.key(3, "view.alpha")
        let undo = model.undoManager

        model.set(opacity, to: .double(0.8), continuous: true)
        let first = await Wait.until {
            await model.state == .loaded(
                Self.replacing("view.alpha", with: .double(0.8), in: layerThree))
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
        let dragged = Self.replacing("view.alpha", with: .double(0.8), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "view.alpha")
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
        let dragged = Self.replacing("view.alpha", with: .double(0.8), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "view.alpha")
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

    // MARK: - C-ATTR-13

    private static func bounds(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AttributeValue {
        .rect(Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height)))
    }

    /// The groups with one attribute's limits replaced, as an answer may give them.
    private static func limiting(
        _ id: String, to limits: [NumberLimit]?, in groups: [AttributeGroup]
    ) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == id { attribute.limits = limits }
                return attribute
            }
            return group
        }
    }

    /// Opacity 1.4, a negative width and a font size of 0 go nowhere and say why; a negative
    /// x, which is free, and values on the bounds go (P-SET-07).
    @MainActor
    func test_C_ATTR_13_aValueOutsideTheLimitsIsNeverSent() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let steps = Self.resultSteps(3, layerThree, as: 30) + Self.resultSteps(3, layerThree, as: 31)
            + Self.resultSteps(3, layerThree, as: 32)
        let (model, session, server) = try await editing(try Self.script(steps))
        let opacity = Self.key(3, "view.alpha")
        let bounds = Self.key(3, "layer.bounds")
        let fontSize = Self.key(3, "label.fontSize")

        model.set(opacity, to: .double(1.4), continuous: false)
        XCTAssertEqual(
            model.edits[opacity],
            .failed(.outOfRange(LimitViolation(
                component: nil, reason: .outOfRange(NumberLimit(minimum: 0, maximum: 1))))))
        model.set(bounds, to: Self.bounds(0, 0, -20, 24), continuous: false)
        XCTAssertEqual(
            model.edits[bounds],
            .failed(.outOfRange(LimitViolation(component: 2, reason: .outOfRange(NumberLimit(minimum: 0))))))
        model.set(fontSize, to: .double(0), continuous: false)
        if case .failed(.outOfRange) = model.edits[fontSize] {} else {
            XCTFail("a font size of 0 is outside > 0")
        }

        model.set(bounds, to: Self.bounds(-20, 0, 200, 24), continuous: false)
        var settled = await Wait.until { await model.edits[bounds] == nil }
        XCTAssertTrue(settled)
        model.set(opacity, to: .double(1), continuous: false)
        settled = await Wait.until { await model.edits[opacity] == nil }
        XCTAssertTrue(settled)
        model.set(bounds, to: Self.bounds(0, 0, 0, 0), continuous: false)
        settled = await Wait.until { await model.edits[bounds] == nil }
        XCTAssertTrue(settled)

        let sent = await Self.sets(server)
        XCTAssertEqual(
            sent.map(\.value), [Self.bounds(-20, 0, 200, 24), .double(1), Self.bounds(0, 0, 0, 0)])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    /// The two requests of `set-attribute-rejected` that are outside the limits are what a
    /// client must not send: this one does not.
    @MainActor
    func test_C_ATTR_13_theFixturesTwoValuesOutsideTheLimitsAreNotSent() async throws {
        let requests = try Fixtures.frames(scenario: "set-attribute-rejected")
            .filter { $0.fileName.contains("out-of-range") || $0.fileName.contains("negative-width") }
            .compactMap { fixture -> SetAttribute? in
                guard case .setAttribute(let request) = try FrameCodec.decode(fixture.payload).body
                else { return nil }
                return request
            }
        XCTAssertEqual(requests.map(\.attributeID), ["view.alpha", "layer.bounds"])
        let (model, session, server) = try await editing(try Self.script([]))
        for request in requests {
            let key = Self.key(request.layerID, try XCTUnwrap(request.attributeID))
            model.set(key, to: request.value, continuous: false)
            if case .failed(.outOfRange) = model.edits[key] {} else {
                XCTFail("\(key.attributeID) was not held back")
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sets(server)
        XCTAssertEqual(sent, [])

        await session.close()
        await server.stop()
    }

    /// A drag past the bound keeps the last value within it, and ends as one step to that
    /// value (C-ATTR-07).
    @MainActor
    func test_C_ATTR_13_aDragThatCrossesTheBoundKeepsItsLastGoodValue() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let dragged = Self.replacing("view.alpha", with: .double(0.8), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "view.alpha")

        model.set(opacity, to: .double(0.8), continuous: true)
        let answered = await Wait.until { await model.state == .loaded(dragged) }
        XCTAssertTrue(answered)
        model.set(opacity, to: .double(1.2), continuous: true)
        XCTAssertEqual(model.edits[opacity], .sending(.double(0.8)), "the last good value")
        model.set(opacity, to: .double(1.3), continuous: false)
        XCTAssertNil(model.edits[opacity])
        XCTAssertTrue(model.undoManager.canUndo, "the drag to 0.8 is one step")
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [.double(0.8)])

        await session.close()
        await server.stop()
    }

    /// A drag held on a bound gives the same value again and again: only the first goes, and
    /// its end sends nothing more (reported by the user: the spinner showed while held).
    @MainActor
    func test_C_ATTR_13_aDragHeldOnTheBoundSendsNothingMore() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let dragged = Self.replacing("view.alpha", with: .double(0.5), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, dragged, as: 30)))
        let opacity = Self.key(3, "view.alpha")

        model.set(opacity, to: .double(0.5), continuous: true)
        model.set(opacity, to: .double(0.5), continuous: true)
        let answered = await Wait.until { await model.state == .loaded(dragged) }
        XCTAssertTrue(answered)
        model.set(opacity, to: .double(0.5), continuous: true)
        model.set(opacity, to: .double(0.5), continuous: false)
        XCTAssertNil(model.edits[opacity], "the drag ended")
        XCTAssertTrue(model.undoManager.canUndo, "one step")
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [.double(0.5)])

        await session.close()
        await server.stop()
    }

    /// Undo and redo send nothing outside the limits the attribute has now; the step fails
    /// and leaves the stack (C-ATTR-08).
    @MainActor
    func test_C_ATTR_13_undoToAValueOutsideTheLimitsIsNotSentAndLeavesTheStack() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let free = NumberLimit()
        // The answer to a width of 10 says widths now go up to 100: 200 is outside.
        let narrowed = Self.limiting(
            "layer.bounds", to: [free, free, NumberLimit(minimum: 0, maximum: 100), NumberLimit(minimum: 0)],
            in: Self.replacing("layer.bounds", with: Self.bounds(0, 0, 10, 24), in: layerThree))
        let fifty = Self.replacing("layer.bounds", with: Self.bounds(0, 0, 50, 24), in: layerThree)
        // The answer to undoing that says widths are now at least 60: redoing 50 is outside.
        let widened = Self.limiting(
            "layer.bounds", to: [free, free, NumberLimit(minimum: 60), NumberLimit(minimum: 0)],
            in: Self.replacing("layer.bounds", with: Self.bounds(0, 0, 10, 24), in: layerThree))
        let steps = Self.resultSteps(3, narrowed, as: 30) + Self.resultSteps(3, fifty, as: 31)
            + Self.resultSteps(3, widened, as: 32)
        let (model, session, server) = try await editing(try Self.script(steps))
        let bounds = Self.key(3, "layer.bounds")
        let undo = model.undoManager

        model.set(bounds, to: Self.bounds(0, 0, 10, 24), continuous: false)
        var done = await Wait.until { @MainActor in model.state == .loaded(narrowed) && model.edits.isEmpty }
        XCTAssertTrue(done)
        undo.undo()
        if case .failed(.outOfRange(let violation)) = model.edits[bounds] {
            XCTAssertEqual(violation.component, 2)
        } else {
            XCTFail("the undo was not held back")
        }
        XCTAssertFalse(undo.canUndo, "the step left the stack")
        XCTAssertFalse(undo.canRedo)

        // Redo: a width of 50, undone, and the answer makes redoing it impossible.
        model.set(bounds, to: Self.bounds(0, 0, 50, 24), continuous: false)
        done = await Wait.until { @MainActor in model.state == .loaded(fifty) && model.edits.isEmpty }
        XCTAssertTrue(done)
        undo.undo()
        done = await Wait.until { @MainActor in model.state == .loaded(widened) && model.edits.isEmpty }
        XCTAssertTrue(done)
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        if case .failed(.outOfRange) = model.edits[bounds] {} else {
            XCTFail("the redo was not held back")
        }
        XCTAssertFalse(undo.canRedo, "the step left the stack")

        let sent = await Self.sets(server)
        XCTAssertEqual(
            sent.map(\.value),
            [Self.bounds(0, 0, 10, 24), Self.bounds(0, 0, 50, 24), Self.bounds(0, 0, 10, 24)])

        await session.close()
        await server.stop()
    }

    /// A width the app set outside the limits itself is shown, and a change that keeps it is
    /// not sent (P-SET-07).
    @MainActor
    func test_C_ATTR_13_anAppSetValueOutsideTheLimitsIsKeptButNotSentAgain() async throws {
        let layerThree = try AttributesStoreTests.layerThree()
        let negative = Self.replacing("layer.bounds", with: Self.bounds(0, 0, -20, 24), in: layerThree)
        let (model, session, server) = try await editing(
            try Self.script(Self.resultSteps(3, negative, as: 30)))
        let bounds = Self.key(3, "layer.bounds")
        // The app answers a change of the height with a negative width of its own.
        model.set(bounds, to: Self.bounds(0, 0, 200, 30), continuous: false)
        let answered = await Wait.until { await model.state == .loaded(negative) }
        XCTAssertTrue(answered)

        model.set(bounds, to: Self.bounds(5, 0, -20, 24), continuous: false)
        if case .failed(.outOfRange(let violation)) = model.edits[bounds] {
            XCTAssertEqual(violation.component, 2)
        } else {
            XCTFail("a value that keeps the negative width was sent")
        }
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sets(server)
        XCTAssertEqual(sent.map(\.value), [Self.bounds(0, 0, 200, 30)])

        await session.close()
        await server.stop()
    }
}
