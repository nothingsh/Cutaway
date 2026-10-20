internal import FlatBuffers
import Foundation

// Generated accessor types to this module's value types. Everything here runs after the
// buffer has been verified.

// MARK: - Geometry

extension Point {
    init(_ wire: Cutaway_Wire_Point) {
        self.init(x: wire.x, y: wire.y)
    }
}

extension Size {
    init(_ wire: Cutaway_Wire_Size) {
        self.init(width: wire.width, height: wire.height)
    }
}

extension Rect {
    init(_ wire: Cutaway_Wire_Rect) {
        self.init(origin: Point(wire.origin), size: Size(wire.size))
    }
}

extension Insets {
    init(_ wire: Cutaway_Wire_Insets) {
        self.init(top: wire.top, left: wire.left_, bottom: wire.bottom, right: wire.right_)
    }
}

extension Color {
    init(_ wire: Cutaway_Wire_Color) {
        self.init(red: wire.red, green: wire.green, blue: wire.blue, alpha: wire.alpha)
    }
}

extension Transform3D {
    init(_ wire: Cutaway_Wire_Transform3D) {
        self.init(
            m11: wire.m11, m12: wire.m12, m13: wire.m13, m14: wire.m14,
            m21: wire.m21, m22: wire.m22, m23: wire.m23, m24: wire.m24,
            m31: wire.m31, m32: wire.m32, m33: wire.m33, m34: wire.m34,
            m41: wire.m41, m42: wire.m42, m43: wire.m43, m44: wire.m44)
    }
}

extension Version {
    init(_ wire: Cutaway_Wire_Version) {
        self.init(major: wire.major, minor: wire.minor)
    }
}

// MARK: - Enums

extension Role {
    init(_ wire: Cutaway_Wire_Role) {
        switch wire {
        case .client: self = .client
        case .server: self = .server
        }
    }
}

extension ErrorCode {
    init(_ wire: Cutaway_Wire_ErrorCode) {
        switch wire {
        case .unknown: self = .unknown
        case .malformedframe: self = .malformedFrame
        case .unexpectedmessage: self = .unexpectedMessage
        case .busy: self = .busy
        case .appnotactive: self = .appNotActive
        case .internal_: self = .internalError
        case .layernotfound: self = .layerNotFound
        case .attributenoteditable: self = .attributeNotEditable
        case .invalidattributevalue: self = .invalidAttributeValue
        case .notsupported: self = .notSupported
        }
    }
}

extension StreamStatus {
    init(_ wire: Cutaway_Wire_StreamStatus) {
        switch wire {
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        case .failed: self = .failed
        }
    }
}

extension AppState {
    init(_ wire: Cutaway_Wire_AppState) {
        switch wire {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        }
    }
}

extension DeviceKind {
    init(_ wire: Cutaway_Wire_DeviceKind) {
        switch wire {
        case .unknown: self = .unknown
        case .phone: self = .phone
        case .pad: self = .pad
        case .mac: self = .mac
        }
    }
}

extension ImageEncoding {
    init(_ wire: Cutaway_Wire_ImageEncoding) {
        switch wire {
        case .bgra8premultipliedlzfse: self = .bgra8PremultipliedLzfse
        }
    }
}

extension NodeKind {
    /// The runtime already reads a value this client does not know as `Layer`.
    init(_ wire: Cutaway_Wire_NodeKind) {
        switch wire {
        case .layer: self = .layer
        case .virtual: self = .virtual
        }
    }
}

extension DetailStatus {
    init(_ wire: Cutaway_Wire_DetailStatus) {
        switch wire {
        case .ok: self = .ok
        case .layernotfound: self = .layerNotFound
        case .capturefailed: self = .captureFailed
        case .excluded: self = .excluded
        }
    }
}

extension AttributeValueKind {
    init(_ wire: Cutaway_Wire_AttributeValueKind) {
        switch wire {
        case .none_: self = .none
        case .boolvalue: self = .bool
        case .intvalue: self = .integer
        case .doublevalue: self = .double
        case .stringvalue: self = .string
        case .colorvalue: self = .color
        case .pointvalue: self = .point
        case .sizevalue: self = .size
        case .rectvalue: self = .rect
        case .insetsvalue: self = .insets
        case .transformvalue: self = .transform
        case .enumvalue: self = .enumeration
        case .layerreferencevalue: self = .references
        }
    }
}

// MARK: - Messages

extension ClientInfo {
    init(_ wire: Cutaway_Wire_ClientInfo) {
        self.init(name: wire.name, version: wire.version)
    }
}

extension AppInfo {
    init(_ wire: Cutaway_Wire_AppInfo) {
        self.init(
            name: wire.name, bundleID: wire.bundleId, appVersion: wire.appVersion,
            deviceName: wire.deviceName, deviceKind: DeviceKind(wire.deviceKind),
            isSimulator: wire.isSimulator, osName: wire.osName, osVersion: wire.osVersion,
            screenSize: wire.screenSize.map { Size($0) }, screenScale: wire.screenScale,
            serverVersion: wire.serverVersion)
    }
}

extension Hello {
    init(_ wire: Cutaway_Wire_Hello) {
        self.init(
            protocolVersion: wire.protocol_.map { Version($0) }, role: Role(wire.role),
            client: wire.client.map { ClientInfo($0) }, app: wire.app.map { AppInfo($0) })
    }
}

extension EncodedImage {
    init(_ wire: Cutaway_Wire_Image) {
        // One copy of the compressed bytes, not an element-by-element append.
        let data = wire.withUnsafePointerToData { bytes, count in
            bytes.baseAddress.map { Data(bytes: $0, count: count) } ?? Data()
        }
        self.init(
            encoding: ImageEncoding(wire.encoding), pixelWidth: wire.pixelWidth,
            pixelHeight: wire.pixelHeight, bytesPerRow: wire.bytesPerRow, scale: wire.scale,
            data: data ?? Data())
    }
}

extension AppIcon {
    init(_ wire: Cutaway_Wire_AppIcon) {
        self.init(image: wire.image.map { EncodedImage($0) })
    }
}

extension LayerNode {
    init(_ wire: Cutaway_Wire_LayerNode) {
        self.init(
            id: wire.id, parentID: wire.parentId, className: wire.className,
            displayClassName: wire.displayClassName, viewClassName: wire.viewClassName,
            viewDisplayClassName: wire.viewDisplayClassName,
            bounds: wire.bounds.map { Rect($0) }, position: wire.position.map { Point($0) },
            anchorPoint: wire.anchorPoint.map { Point($0) },
            transform: wire.transform.map { Transform3D($0) }, zPosition: wire.zPosition,
            isHidden: wire.hidden, opacity: wire.opacity, masksToBounds: wire.masksToBounds,
            viewControllerClassName: wire.viewControllerClassName,
            viewControllerDisplayClassName: wire.viewControllerDisplayClassName,
            memberReferences: wire.memberReferences.map { MemberReference($0) },
            layerAddress: Self.address(wire.layerAddress), viewAddress: Self.address(wire.viewAddress),
            viewControllerAddress: Self.address(wire.viewControllerAddress),
            layerClassOrigin: ClassOrigin(wire.layerClassOrigin),
            viewClassOrigin: ClassOrigin(wire.viewClassOrigin),
            viewControllerClassOrigin: ClassOrigin(wire.viewControllerClassOrigin),
            layerBaseClassName: nonEmpty(wire.layerBaseClassName),
            viewBaseClassName: nonEmpty(wire.viewBaseClassName),
            viewControllerVisibility: ViewControllerVisibility(wire.viewControllerVisibility),
            kind: NodeKind(wire.nodeKind), name: nonEmpty(wire.name),
            isCollapsedByDefault: wire.collapsedByDefault, isCaptureExcluded: wire.captureExcluded)
    }

    /// 0 means absent (P-HIER-14).
    private static func address(_ wire: UInt64) -> UInt64? {
        wire == 0 ? nil : wire
    }
}

/// A protocol 1.1 string field whose empty value means nothing but absent (C-WIRE-11).
private func nonEmpty(_ string: String?) -> String? {
    guard let string, !string.isEmpty else { return nil }
    return string
}

extension ClassOrigin {
    /// The runtime already reads a value this client does not know as `Unknown`.
    init(_ wire: Cutaway_Wire_Origin) {
        switch wire {
        case .unknown: self = .unknown
        case .system: self = .system
        case .app: self = .app
        }
    }
}

extension ViewControllerVisibility {
    init(_ wire: Cutaway_Wire_ViewControllerVisibility) {
        switch wire {
        case .unknown: self = .unknown
        case .shown: self = .shown
        case .notshown: self = .notShown
        }
    }
}

extension MemberReference {
    init(_ wire: Cutaway_Wire_MemberReference) {
        self.init(
            ownerClassName: wire.ownerClassName,
            ownerDisplayClassName: wire.ownerDisplayClassName, name: wire.name)
    }
}

extension Hierarchy {
    init(_ wire: Cutaway_Wire_Hierarchy) {
        self.init(nodes: wire.nodes.map { LayerNode($0) }, keyWindowID: wire.keyWindowId)
    }
}

extension LayerDetailRequest {
    init(_ wire: Cutaway_Wire_LayerDetailRequest) {
        self.init(
            layerID: wire.layerId, wantSolo: wire.wantSolo, wantGroup: wire.wantGroup,
            wantAttributes: wire.wantAttributes, wantConstraints: wire.wantConstraints)
    }
}

extension GetLayerDetails {
    init(_ wire: Cutaway_Wire_GetLayerDetails) {
        self.init(
            requests: wire.requests.map { LayerDetailRequest($0) },
            maxTextureDimension: wire.maxTextureDimension)
    }
}

/// A table with an `AttributeValue` field: `Attribute` and `SetAttribute`.
protocol WireAttributeValueHolder {
    var valueType: Cutaway_Wire_AttributeValue { get }
    func value<T: FlatbuffersInitializable>(type: T.Type) -> T?
}

extension Cutaway_Wire_Attribute: WireAttributeValueHolder {}
extension Cutaway_Wire_SetAttribute: WireAttributeValueHolder {}

extension AttributeValue {
    /// Nil when the attribute has no value. A value table whose own field is absent is
    /// degenerate; it reads as that type's zero value rather than as nil, so that "no value"
    /// keeps the single meaning P-ATTR-02 gives it.
    init?(_ wire: some WireAttributeValueHolder) {
        switch wire.valueType {
        case .none_:
            return nil
        case .boolvalue:
            guard let table = wire.value(type: Cutaway_Wire_BoolValue.self) else { return nil }
            self = .bool(table.value)
        case .intvalue:
            guard let table = wire.value(type: Cutaway_Wire_IntValue.self) else { return nil }
            self = .integer(table.value)
        case .doublevalue:
            guard let table = wire.value(type: Cutaway_Wire_DoubleValue.self) else { return nil }
            self = .double(table.value)
        case .stringvalue:
            guard let table = wire.value(type: Cutaway_Wire_StringValue.self) else { return nil }
            self = .string(table.value ?? "")
        case .colorvalue:
            guard let table = wire.value(type: Cutaway_Wire_ColorValue.self) else { return nil }
            self = .color(table.value.map { Color($0) } ?? .zero)
        case .pointvalue:
            guard let table = wire.value(type: Cutaway_Wire_PointValue.self) else { return nil }
            self = .point(table.value.map { Point($0) } ?? .zero)
        case .sizevalue:
            guard let table = wire.value(type: Cutaway_Wire_SizeValue.self) else { return nil }
            self = .size(table.value.map { Size($0) } ?? .zero)
        case .rectvalue:
            guard let table = wire.value(type: Cutaway_Wire_RectValue.self) else { return nil }
            self = .rect(table.value.map { Rect($0) } ?? .zero)
        case .insetsvalue:
            guard let table = wire.value(type: Cutaway_Wire_InsetsValue.self) else { return nil }
            self = .insets(table.value.map { Insets($0) } ?? .zero)
        case .transformvalue:
            guard let table = wire.value(type: Cutaway_Wire_TransformValue.self) else { return nil }
            self = .transform(table.value.map { Transform3D($0) } ?? .zero)
        case .enumvalue:
            guard let table = wire.value(type: Cutaway_Wire_EnumValue.self) else { return nil }
            self = .enumeration(EnumValue(
                value: table.value, cases: table.cases.map { $0 ?? "" }, caseName: table.caseName,
                caseValues: Array(table.caseValues)))
        case .layerreferencevalue:
            guard let table = wire.value(type: Cutaway_Wire_LayerReferenceValue.self)
            else { return nil }
            self = .references(table.references.compactMap { ObjectReference($0) })
        }
    }
}

extension ObjectReference {
    /// Nil for an entry with no name at all (C-WIRE-12).
    init?(_ wire: Cutaway_Wire_ObjectReference) {
        let className = nonEmpty(wire.className)
        guard let displayClassName = nonEmpty(wire.displayClassName) ?? className else { return nil }
        self.init(
            layerID: wire.layerId == 0 ? nil : wire.layerId, className: className,
            displayClassName: displayClassName)
    }
}

extension Attribute {
    init(_ wire: Cutaway_Wire_Attribute) {
        self.init(
            id: wire.id, title: wire.title, value: AttributeValue(wire), editable: wire.editable,
            acceptsNil: wire.acceptsNil, valueKind: AttributeValueKind(wire.valueKind),
            section: AttributeSection(wire.section))
        // A unit on a kind that cannot have one is read as none (P-ATTR-14, C-WIRE-11).
        if valueKind.mayHaveUnit { unit = AttributeUnit(wire.unit) }
        limits = Self.limits(
            wire.limits.map { NumberLimit($0) }, editable: editable, kind: valueKind)
        // P-ATTR-12 gives both or neither; one alone is read as neither (C-WIRE-11).
        if let name = nonEmpty(wire.cluster), let slot = nonEmpty(wire.slot) {
            cluster = AttributeCluster(name: name, slot: slot)
        }
        inactiveCause = nonEmpty(wire.inactiveCause)
        if wire.valueType == .colorvalue, let color = wire.value(type: Cutaway_Wire_ColorValue.self) {
            systemColorName = nonEmpty(color.systemName)
            registeredColorName = nonEmpty(color.name)
            // P-ATTR-17 gives both or neither; one alone is read as neither (C-WIRE-12).
            if let light = color.light, let dark = color.dark {
                appearanceColors = AppearanceColors(light: Color(light), dark: Color(dark))
            }
        }
    }

    /// The limits as P-ATTR-09 and P-ATTR-10 allow them, or nil (C-WIRE-10): only for an
    /// editable number of a kind that has them, with one entry or one per component, each
    /// entry finite and with some value between its bounds (a whole one for an integer).
    /// Anything else is read as no limits rather than fail the decoding.
    static func limits(
        _ limits: [NumberLimit], editable: Bool, kind: AttributeValueKind
    ) -> [NumberLimit]? {
        guard editable, let count = kind.numericComponentCount, !limits.isEmpty,
              limits.count == 1 || limits.count == count,
              limits.allSatisfy({ $0.isValid(integer: kind == .integer) })
        else { return nil }
        return limits
    }
}

extension AttributeSection {
    /// The runtime already reads a value this client does not know as `Unspecified`.
    init(_ wire: Cutaway_Wire_AttributeSection) {
        switch wire {
        case .unspecified: self = .unspecified
        case .identity: self = .identity
        case .general: self = .general
        case .layout: self = .layout
        case .content: self = .content
        case .appearance: self = .appearance
        case .behavior: self = .behavior
        case .accessibility: self = .accessibility
        }
    }
}

extension AttributeUnit {
    /// The runtime already reads a value this client does not know as `Unspecified`.
    init(_ wire: Cutaway_Wire_AttributeUnit) {
        switch wire {
        case .unspecified: self = .unspecified
        case .points: self = .points
        case .fraction: self = .fraction
        }
    }
}

extension NumberLimit {
    /// A side whose `has_` field is false is free; its other two fields are ignored.
    init(_ wire: Cutaway_Wire_NumberLimit) {
        self.init(
            minimum: wire.hasMinimum ? wire.minimum : nil,
            minimumIsExclusive: wire.hasMinimum && wire.minimumExclusive,
            maximum: wire.hasMaximum ? wire.maximum : nil,
            maximumIsExclusive: wire.hasMaximum && wire.maximumExclusive)
    }

    /// Whether the entry is one P-ATTR-10 allows: finite bounds, integers for an integer,
    /// and some value (a whole one for an integer) between them.
    func isValid(integer: Bool) -> Bool {
        let bounds = [minimum, maximum].compactMap { $0 }
        guard bounds.allSatisfy(\.isFinite) else { return false }
        if integer, !bounds.allSatisfy({ $0.rounded() == $0 }) { return false }
        guard let minimum, let maximum else { return true }
        if integer {
            let lowest = minimumIsExclusive ? minimum + 1 : minimum
            let highest = maximumIsExclusive ? maximum - 1 : maximum
            return lowest <= highest
        }
        if minimumIsExclusive || maximumIsExclusive { return minimum < maximum }
        return minimum <= maximum
    }
}

extension AttributeGroup {
    init(_ wire: Cutaway_Wire_AttributeGroup) {
        self.init(
            id: wire.id, title: wire.title, attributes: wire.attributes.map { Attribute($0) },
            className: nonEmpty(wire.className), isFromApp: wire.fromApp)
    }
}

extension LayerDetail {
    init(_ wire: Cutaway_Wire_LayerDetail) {
        self.init(
            layerID: wire.layerId, status: DetailStatus(wire.status),
            solo: wire.solo.map { EncodedImage($0) }, group: wire.group.map { EncodedImage($0) },
            attributeGroups: wire.attributeGroups.map { AttributeGroup($0) },
            constraints: wire.constraints.map { LayoutConstraint($0) })
    }
}

extension LayerDetailsChunk {
    init(_ wire: Cutaway_Wire_LayerDetailsChunk) {
        self.init(sequence: wire.sequence, details: wire.details.map { LayerDetail($0) })
    }
}

// MARK: - Layout (protocol 0.4)

extension LayoutAttribute {
    /// The raw values are NSLayoutConstraint.Attribute's on both sides. The pinned runtime
    /// already reads a value the protocol does not name as `NotAnAttribute` (P-LAYOUT-08).
    init(_ wire: Cutaway_Wire_LayoutAttribute) {
        self = LayoutAttribute(rawValue: wire.rawValue) ?? .notAnAttribute
    }
}

extension LayoutRelation {
    init(_ wire: Cutaway_Wire_LayoutRelation) {
        switch wire {
        case .equal: self = .equal
        case .lessthanorequal: self = .lessThanOrEqual
        case .greaterthanorequal: self = .greaterThanOrEqual
        }
    }
}

extension ConstraintStatus {
    init(_ wire: Cutaway_Wire_ConstraintStatus) {
        switch wire {
        case .unknown: self = .unknown
        case .satisfied: self = .satisfied
        case .unsatisfied: self = .unsatisfied
        }
    }
}

extension LayoutItem {
    init(_ wire: Cutaway_Wire_LayoutItem) {
        switch wire.kind {
        case .view:
            self = .view(layerID: wire.layerId)
        case .layoutguide:
            self = .layoutGuide(LayoutGuide(
                ownerLayerID: wire.layerId, guideID: wire.guideId, className: wire.className,
                displayClassName: wire.displayClassName, identifier: wire.identifier,
                frame: wire.guideFrame.map { Rect($0) }, kind: LayoutGuideKind(wire.guideKind)))
        case .other:
            self = .other(className: wire.className, displayClassName: wire.displayClassName)
        }
    }
}

extension LayoutConstraint {
    init(_ wire: Cutaway_Wire_LayoutConstraint) {
        self.init(
            id: wire.id, className: wire.className, identifier: wire.identifier,
            firstItem: wire.firstItem.map { LayoutItem($0) },
            firstAttribute: LayoutAttribute(wire.firstAttribute),
            relation: LayoutRelation(wire.relation),
            secondItem: wire.secondItem.map { LayoutItem($0) },
            secondAttribute: LayoutAttribute(wire.secondAttribute), multiplier: wire.multiplier,
            constant: wire.constant, priority: wire.priority, status: ConstraintStatus(wire.status),
            origin: ClassOrigin(wire.origin))
    }
}

extension LayoutGuideKind {
    /// The runtime already reads a value this client does not know as `Unknown`.
    init(_ wire: Cutaway_Wire_LayoutGuideKind) {
        switch wire {
        case .unknown: self = .unknown
        case .other: self = .other
        case .safearea: self = .safeArea
        case .layoutmargins: self = .layoutMargins
        case .readablecontent: self = .readableContent
        case .keyboard: self = .keyboard
        }
    }
}

extension SetAttribute {
    init(_ wire: Cutaway_Wire_SetAttribute) {
        self.init(
            layerID: wire.layerId, attributeID: wire.attributeId, value: AttributeValue(wire))
    }
}

extension SetAttributeResult {
    init(_ wire: Cutaway_Wire_SetAttributeResult) {
        self.init(
            layerID: wire.layerId,
            attributeGroups: wire.attributeGroups.map { AttributeGroup($0) })
    }
}

extension ServerError {
    init(_ wire: Cutaway_Wire_Error) {
        self.init(code: ErrorCode(wire.code), message: wire.message)
    }
}

extension StreamEnd {
    init(_ wire: Cutaway_Wire_StreamEnd) {
        self.init(
            status: StreamStatus(wire.status), chunkCount: wire.chunkCount,
            error: wire.error.map { ServerError($0) })
    }
}

extension Cancel {
    init(_ wire: Cutaway_Wire_Cancel) {
        self.init(targetRequestID: wire.targetRequestId)
    }
}

extension Frame {
    init(_ wire: Cutaway_Wire_Frame) {
        let body: Body?
        switch wire.bodyType {
        case .none_:
            body = nil
        case .hello:
            body = wire.body(type: Cutaway_Wire_Hello.self).map { .hello(Hello($0)) }
        case .getappicon:
            body = .getAppIcon
        case .appicon:
            body = wire.body(type: Cutaway_Wire_AppIcon.self).map { .appIcon(AppIcon($0)) }
        case .gethierarchy:
            body = .getHierarchy
        case .hierarchy:
            body = wire.body(type: Cutaway_Wire_Hierarchy.self).map { .hierarchy(Hierarchy($0)) }
        case .getlayerdetails:
            body = wire.body(type: Cutaway_Wire_GetLayerDetails.self)
                .map { .getLayerDetails(GetLayerDetails($0)) }
        case .layerdetailschunk:
            body = wire.body(type: Cutaway_Wire_LayerDetailsChunk.self)
                .map { .layerDetailsChunk(LayerDetailsChunk($0)) }
        case .streamend:
            body = wire.body(type: Cutaway_Wire_StreamEnd.self).map { .streamEnd(StreamEnd($0)) }
        case .cancel:
            body = wire.body(type: Cutaway_Wire_Cancel.self).map { .cancel(Cancel($0)) }
        case .error:
            body = wire.body(type: Cutaway_Wire_Error.self).map { .error(ServerError($0)) }
        case .appstatechanged:
            body = wire.body(type: Cutaway_Wire_AppStateChanged.self)
                .map { .appStateChanged(AppState($0.state)) }
        case .setattribute:
            body = wire.body(type: Cutaway_Wire_SetAttribute.self)
                .map { .setAttribute(SetAttribute($0)) }
        case .setattributeresult:
            body = wire.body(type: Cutaway_Wire_SetAttributeResult.self)
                .map { .setAttributeResult(SetAttributeResult($0)) }
        case .getsubtree:
            body = wire.body(type: Cutaway_Wire_GetSubtree.self)
                .map { .getSubtree(GetSubtree(rootID: $0.rootId)) }
        case .getenvironment:
            body = .getEnvironment
        case .setenvironment:
            body = wire.body(type: Cutaway_Wire_SetEnvironment.self)
                .map { .setEnvironment(SetEnvironment(overrides: Traits($0.overrides))) }
        case .environment:
            body = wire.body(type: Cutaway_Wire_Environment.self).map { environment in
                let overridable = wire.body(type: RawEnvironment.self)?.overridable ?? []
                return .environment(Environment(environment, overridable: overridable))
            }
        }
        self.init(requestID: wire.requestId, body: body)
    }
}

// MARK: - Environment

extension Traits {
    /// Absent reads as all `unspecified` (P-ENV-01). The runtime already reads a value this
    /// client does not know as `Unspecified`.
    init(_ wire: Cutaway_Wire_Traits?) {
        guard let wire else {
            self = .unspecified
            return
        }
        self.init(
            userInterfaceStyle: UserInterfaceStyle(wire.userInterfaceStyle),
            contentSizeCategory: ContentSizeCategory(wire.contentSizeCategory),
            layoutDirection: LayoutDirection(wire.layoutDirection),
            horizontalSizeClass: SizeClass(wire.horizontalSizeClass),
            verticalSizeClass: SizeClass(wire.verticalSizeClass))
    }
}

extension UserInterfaceStyle {
    init(_ wire: Cutaway_Wire_UserInterfaceStyle) {
        switch wire {
        case .unspecified: self = .unspecified
        case .light: self = .light
        case .dark: self = .dark
        }
    }
}

extension ContentSizeCategory {
    init(_ wire: Cutaway_Wire_ContentSizeCategory) {
        switch wire {
        case .unspecified: self = .unspecified
        case .extrasmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extralarge: self = .extraLarge
        case .extraextralarge: self = .extraExtraLarge
        case .extraextraextralarge: self = .extraExtraExtraLarge
        case .accessibilitymedium: self = .accessibilityMedium
        case .accessibilitylarge: self = .accessibilityLarge
        case .accessibilityextralarge: self = .accessibilityExtraLarge
        case .accessibilityextraextralarge: self = .accessibilityExtraExtraLarge
        case .accessibilityextraextraextralarge: self = .accessibilityExtraExtraExtraLarge
        }
    }
}

extension LayoutDirection {
    init(_ wire: Cutaway_Wire_LayoutDirection) {
        switch wire {
        case .unspecified: self = .unspecified
        case .lefttoright: self = .leftToRight
        case .righttoleft: self = .rightToLeft
        }
    }
}

extension SizeClass {
    init(_ wire: Cutaway_Wire_SizeClass) {
        switch wire {
        case .unspecified: self = .unspecified
        case .compact: self = .compact
        case .regular: self = .regular
        }
    }
}

extension TraitKind {
    /// Nil for a kind this client does not know.
    init?(raw: UInt8) {
        switch Cutaway_Wire_TraitKind(rawValue: raw) {
        case .userinterfacestyle: self = .userInterfaceStyle
        case .contentsizecategory: self = .contentSizeCategory
        case .layoutdirection: self = .layoutDirection
        case .horizontalsizeclass: self = .horizontalSizeClass
        case .verticalsizeclass: self = .verticalSizeClass
        case nil: return nil
        }
    }
}

extension Environment {
    init(_ wire: Cutaway_Wire_Environment, overridable: [TraitKind]) {
        self.init(
            overrides: Traits(wire.overrides), current: Traits(wire.current),
            overridable: overridable)
    }
}

/// `Environment` as a plain table, for the one field the generated accessor cannot be used
/// for: it reads a value of an enum vector that this client does not know as the enum's first
/// member, so an unknown kind of trait would become `UserInterfaceStyle`.
private struct RawEnvironment: FlatbuffersInitializable {
    private let table: Table

    init(_ bb: ByteBuffer, o: Int32) {
        table = Table(bb: bb, position: o)
    }

    /// `overridable`, the table's third field: its vtable slot is 4 + 2 × 2. The schema only
    /// appends fields, so the slot never moves. Kinds this client does not know are left out,
    /// and so are repeats, which P-ENV-01 rules out (C-WIRE-12).
    var overridable: [TraitKind] {
        let raw: [UInt8] = table.getVector(at: 8) ?? []
        var kinds: [TraitKind] = []
        for kind in raw.compactMap(TraitKind.init(raw:)) where !kinds.contains(kind) {
            kinds.append(kind)
        }
        return kinds
    }
}
