internal import FlatBuffers
import Foundation

// This module's value types to the generated object-API classes. The classes' parameterless
// initialisers fill sub-tables and structs with default objects, so every field is assigned
// here, nil included.

// MARK: - Geometry

extension Point {
    var wire: Cutaway_Wire_Point { Cutaway_Wire_Point(x: x, y: y) }
}

extension Size {
    var wire: Cutaway_Wire_Size { Cutaway_Wire_Size(width: width, height: height) }
}

extension Rect {
    var wire: Cutaway_Wire_Rect { Cutaway_Wire_Rect(origin: origin.wire, size: size.wire) }
}

extension Insets {
    var wire: Cutaway_Wire_Insets {
        Cutaway_Wire_Insets(top: top, left_: left, bottom: bottom, right_: right)
    }
}

extension Color {
    var wire: Cutaway_Wire_Color {
        Cutaway_Wire_Color(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Transform3D {
    var wire: Cutaway_Wire_Transform3D {
        Cutaway_Wire_Transform3D(
            m11: m11, m12: m12, m13: m13, m14: m14,
            m21: m21, m22: m22, m23: m23, m24: m24,
            m31: m31, m32: m32, m33: m33, m34: m34,
            m41: m41, m42: m42, m43: m43, m44: m44)
    }
}

extension Version {
    var wire: Cutaway_Wire_Version { Cutaway_Wire_Version(major: major, minor: minor) }
}

// MARK: - Enums

extension Role {
    var wire: Cutaway_Wire_Role {
        switch self {
        case .client: return .client
        case .server: return .server
        }
    }
}

extension ErrorCode {
    var wire: Cutaway_Wire_ErrorCode {
        switch self {
        case .unknown: return .unknown
        case .malformedFrame: return .malformedframe
        case .unexpectedMessage: return .unexpectedmessage
        case .busy: return .busy
        case .appNotActive: return .appnotactive
        case .internalError: return .internal_
        case .layerNotFound: return .layernotfound
        case .attributeNotEditable: return .attributenoteditable
        case .invalidAttributeValue: return .invalidattributevalue
        case .notSupported: return .notsupported
        }
    }
}

extension StreamStatus {
    var wire: Cutaway_Wire_StreamStatus {
        switch self {
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }
}

extension AppState {
    var wire: Cutaway_Wire_AppState {
        switch self {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        }
    }
}

extension DeviceKind {
    var wire: Cutaway_Wire_DeviceKind {
        switch self {
        case .unknown: return .unknown
        case .phone: return .phone
        case .pad: return .pad
        case .mac: return .mac
        }
    }
}

extension ImageEncoding {
    var wire: Cutaway_Wire_ImageEncoding {
        switch self {
        case .bgra8PremultipliedLzfse: return .bgra8premultipliedlzfse
        }
    }
}

extension DetailStatus {
    var wire: Cutaway_Wire_DetailStatus {
        switch self {
        case .ok: return .ok
        case .layerNotFound: return .layernotfound
        case .captureFailed: return .capturefailed
        }
    }
}

extension AttributeValueKind {
    var wire: Cutaway_Wire_AttributeValueKind {
        switch self {
        case .none: return .none_
        case .bool: return .boolvalue
        case .integer: return .intvalue
        case .double: return .doublevalue
        case .string: return .stringvalue
        case .color: return .colorvalue
        case .point: return .pointvalue
        case .size: return .sizevalue
        case .rect: return .rectvalue
        case .insets: return .insetsvalue
        case .transform: return .transformvalue
        case .enumeration: return .enumvalue
        case .references: return .layerreferencevalue
        }
    }
}

// MARK: - Messages

extension ClientInfo {
    func makeObject() -> Cutaway_Wire_ClientInfoT {
        let object = Cutaway_Wire_ClientInfoT()
        object.name = name
        object.version = version
        return object
    }
}

extension AppInfo {
    func makeObject() -> Cutaway_Wire_AppInfoT {
        let object = Cutaway_Wire_AppInfoT()
        object.name = name
        object.bundleId = bundleID
        object.appVersion = appVersion
        object.deviceName = deviceName
        object.deviceKind = deviceKind.wire
        object.isSimulator = isSimulator
        object.osName = osName
        object.osVersion = osVersion
        object.screenSize = screenSize?.wire
        object.screenScale = screenScale
        object.serverVersion = serverVersion
        return object
    }
}

extension Hello {
    func makeObject() -> Cutaway_Wire_HelloT {
        let object = Cutaway_Wire_HelloT()
        object.protocol_ = protocolVersion?.wire
        object.role = role.wire
        object.client = client?.makeObject()
        object.app = app?.makeObject()
        return object
    }
}

extension EncodedImage {
    func makeObject() -> Cutaway_Wire_ImageT {
        let object = Cutaway_Wire_ImageT()
        object.encoding = encoding.wire
        object.pixelWidth = pixelWidth
        object.pixelHeight = pixelHeight
        object.bytesPerRow = bytesPerRow
        object.scale = scale
        object.data = [UInt8](data)
        return object
    }
}

extension AppIcon {
    func makeObject() -> Cutaway_Wire_AppIconT {
        let object = Cutaway_Wire_AppIconT()
        object.image = image?.makeObject()
        return object
    }
}

extension LayerNode {
    func makeObject() -> Cutaway_Wire_LayerNodeT {
        let object = Cutaway_Wire_LayerNodeT()
        object.id = id
        object.parentId = parentID
        object.className = className
        object.displayClassName = displayClassName
        object.viewClassName = viewClassName
        object.viewDisplayClassName = viewDisplayClassName
        object.bounds = bounds?.wire
        object.position = position?.wire
        object.anchorPoint = anchorPoint?.wire
        object.transform = transform?.wire
        object.zPosition = zPosition
        object.hidden = isHidden
        object.opacity = opacity
        object.masksToBounds = masksToBounds
        object.viewControllerClassName = viewControllerClassName
        object.viewControllerDisplayClassName = viewControllerDisplayClassName
        object.memberReferences = memberReferences.map { $0.makeObject() }
        object.layerAddress = layerAddress ?? 0
        object.viewAddress = viewAddress ?? 0
        object.viewControllerAddress = viewControllerAddress ?? 0
        object.layerClassOrigin = layerClassOrigin.wire
        object.viewClassOrigin = viewClassOrigin.wire
        object.viewControllerClassOrigin = viewControllerClassOrigin.wire
        object.layerBaseClassName = layerBaseClassName
        object.viewBaseClassName = viewBaseClassName
        object.viewControllerVisibility = viewControllerVisibility.wire
        return object
    }
}

extension ClassOrigin {
    var wire: Cutaway_Wire_Origin {
        switch self {
        case .unknown: return .unknown
        case .system: return .system
        case .app: return .app
        }
    }
}

extension ViewControllerVisibility {
    var wire: Cutaway_Wire_ViewControllerVisibility {
        switch self {
        case .unknown: return .unknown
        case .shown: return .shown
        case .notShown: return .notshown
        }
    }
}

extension MemberReference {
    func makeObject() -> Cutaway_Wire_MemberReferenceT {
        let object = Cutaway_Wire_MemberReferenceT()
        object.ownerClassName = ownerClassName
        object.ownerDisplayClassName = ownerDisplayClassName
        object.name = name
        return object
    }
}

extension Hierarchy {
    func makeObject() -> Cutaway_Wire_HierarchyT {
        let object = Cutaway_Wire_HierarchyT()
        object.nodes = nodes.map { $0.makeObject() }
        object.keyWindowId = keyWindowID
        return object
    }
}

extension LayerDetailRequest {
    func makeObject() -> Cutaway_Wire_LayerDetailRequestT {
        let object = Cutaway_Wire_LayerDetailRequestT()
        object.layerId = layerID
        object.wantSolo = wantSolo
        object.wantGroup = wantGroup
        object.wantAttributes = wantAttributes
        object.wantConstraints = wantConstraints
        return object
    }
}

extension GetLayerDetails {
    func makeObject() -> Cutaway_Wire_GetLayerDetailsT {
        let object = Cutaway_Wire_GetLayerDetailsT()
        object.requests = requests.map { $0.makeObject() }
        object.maxTextureDimension = maxTextureDimension
        return object
    }
}

extension AttributeValue {
    func makeUnion() -> Cutaway_Wire_AttributeValueUnion {
        switch self {
        case .bool(let value):
            let object = Cutaway_Wire_BoolValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .boolvalue)
        case .integer(let value):
            let object = Cutaway_Wire_IntValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .intvalue)
        case .double(let value):
            let object = Cutaway_Wire_DoubleValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .doublevalue)
        case .string(let value):
            let object = Cutaway_Wire_StringValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .stringvalue)
        case .color(let value):
            let object = Cutaway_Wire_ColorValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .colorvalue)
        case .point(let value):
            let object = Cutaway_Wire_PointValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .pointvalue)
        case .size(let value):
            let object = Cutaway_Wire_SizeValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .sizevalue)
        case .rect(let value):
            let object = Cutaway_Wire_RectValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .rectvalue)
        case .insets(let value):
            let object = Cutaway_Wire_InsetsValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .insetsvalue)
        case .transform(let value):
            let object = Cutaway_Wire_TransformValueT()
            object.value = value.wire
            return Cutaway_Wire_AttributeValueUnion(object, type: .transformvalue)
        case .enumeration(let value):
            let object = Cutaway_Wire_EnumValueT()
            object.value = value.value
            object.cases = value.cases
            object.caseName = value.caseName
            object.caseValues = value.caseValues
            return Cutaway_Wire_AttributeValueUnion(object, type: .enumvalue)
        case .references(let references):
            let object = Cutaway_Wire_LayerReferenceValueT()
            object.references = references.map { $0.makeObject() }
            return Cutaway_Wire_AttributeValueUnion(object, type: .layerreferencevalue)
        }
    }
}

extension ObjectReference {
    func makeObject() -> Cutaway_Wire_ObjectReferenceT {
        let object = Cutaway_Wire_ObjectReferenceT()
        object.layerId = layerID ?? 0
        object.className = className
        object.displayClassName = displayClassName
        return object
    }
}

extension Attribute {
    func makeObject() -> Cutaway_Wire_AttributeT {
        let object = Cutaway_Wire_AttributeT()
        object.id = id
        object.title = title
        object.value = value?.makeUnion()
        object.editable = editable
        object.acceptsNil = acceptsNil
        object.valueKind = valueKind.wire
        object.section = section.wire
        object.limits = (limits ?? []).map { $0.makeObject() }
        object.cluster = cluster?.name
        object.slot = cluster?.slot
        object.inactiveCause = inactiveCause
        object.unit = unit.wire
        if let color = object.value?.value as? Cutaway_Wire_ColorValueT {
            color.systemName = systemColorName
            color.light = appearanceColors?.light.wire
            color.dark = appearanceColors?.dark.wire
        }
        return object
    }
}

extension AttributeUnit {
    var wire: Cutaway_Wire_AttributeUnit {
        switch self {
        case .unspecified: return .unspecified
        case .points: return .points
        case .fraction: return .fraction
        }
    }
}

extension AttributeSection {
    var wire: Cutaway_Wire_AttributeSection {
        switch self {
        case .unspecified: return .unspecified
        case .identity: return .identity
        case .general: return .general
        case .layout: return .layout
        case .content: return .content
        case .appearance: return .appearance
        case .behavior: return .behavior
        case .accessibility: return .accessibility
        }
    }
}

extension NumberLimit {
    func makeObject() -> Cutaway_Wire_NumberLimitT {
        let object = Cutaway_Wire_NumberLimitT()
        object.hasMinimum = minimum != nil
        object.minimum = minimum ?? 0
        object.minimumExclusive = minimum != nil && minimumIsExclusive
        object.hasMaximum = maximum != nil
        object.maximum = maximum ?? 0
        object.maximumExclusive = maximum != nil && maximumIsExclusive
        return object
    }
}

extension AttributeGroup {
    func makeObject() -> Cutaway_Wire_AttributeGroupT {
        let object = Cutaway_Wire_AttributeGroupT()
        object.id = id
        object.title = title
        object.attributes = attributes.map { $0.makeObject() }
        object.className = className
        return object
    }
}

extension LayerDetail {
    func makeObject() -> Cutaway_Wire_LayerDetailT {
        let object = Cutaway_Wire_LayerDetailT()
        object.layerId = layerID
        object.status = status.wire
        object.solo = solo?.makeObject()
        object.group = group?.makeObject()
        object.attributeGroups = attributeGroups.map { $0.makeObject() }
        object.constraints = constraints.map { $0.makeObject() }
        return object
    }
}

extension LayerDetailsChunk {
    func makeObject() -> Cutaway_Wire_LayerDetailsChunkT {
        let object = Cutaway_Wire_LayerDetailsChunkT()
        object.sequence = sequence
        object.details = details.map { $0.makeObject() }
        return object
    }
}

extension SetAttribute {
    func makeObject() -> Cutaway_Wire_SetAttributeT {
        let object = Cutaway_Wire_SetAttributeT()
        object.layerId = layerID
        object.attributeId = attributeID
        // Nil writes no value and leaves the union's type NONE (P-SET-02).
        object.value = value?.makeUnion()
        return object
    }
}

extension SetAttributeResult {
    func makeObject() -> Cutaway_Wire_SetAttributeResultT {
        let object = Cutaway_Wire_SetAttributeResultT()
        object.layerId = layerID
        object.attributeGroups = attributeGroups.map { $0.makeObject() }
        return object
    }
}

extension ServerError {
    func makeObject() -> Cutaway_Wire_ErrorT {
        let object = Cutaway_Wire_ErrorT()
        object.code = code.wire
        object.message = message
        return object
    }
}

extension StreamEnd {
    func makeObject() -> Cutaway_Wire_StreamEndT {
        let object = Cutaway_Wire_StreamEndT()
        object.status = status.wire
        object.chunkCount = chunkCount
        object.error = error?.makeObject()
        return object
    }
}

extension Cancel {
    func makeObject() -> Cutaway_Wire_CancelT {
        let object = Cutaway_Wire_CancelT()
        object.targetRequestId = targetRequestID
        return object
    }
}

extension Body {
    func makeUnion() -> Cutaway_Wire_BodyUnion {
        switch self {
        case .hello(let hello):
            return Cutaway_Wire_BodyUnion(hello.makeObject(), type: .hello)
        case .getAppIcon:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetAppIconT(), type: .getappicon)
        case .appIcon(let icon):
            return Cutaway_Wire_BodyUnion(icon.makeObject(), type: .appicon)
        case .getHierarchy:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetHierarchyT(), type: .gethierarchy)
        case .hierarchy(let hierarchy):
            return Cutaway_Wire_BodyUnion(hierarchy.makeObject(), type: .hierarchy)
        case .getLayerDetails(let request):
            return Cutaway_Wire_BodyUnion(request.makeObject(), type: .getlayerdetails)
        case .layerDetailsChunk(let chunk):
            return Cutaway_Wire_BodyUnion(chunk.makeObject(), type: .layerdetailschunk)
        case .streamEnd(let end):
            return Cutaway_Wire_BodyUnion(end.makeObject(), type: .streamend)
        case .cancel(let cancel):
            return Cutaway_Wire_BodyUnion(cancel.makeObject(), type: .cancel)
        case .error(let error):
            return Cutaway_Wire_BodyUnion(error.makeObject(), type: .error)
        case .appStateChanged(let state):
            let object = Cutaway_Wire_AppStateChangedT()
            object.state = state.wire
            return Cutaway_Wire_BodyUnion(object, type: .appstatechanged)
        case .setAttribute(let request):
            return Cutaway_Wire_BodyUnion(request.makeObject(), type: .setattribute)
        case .setAttributeResult(let result):
            return Cutaway_Wire_BodyUnion(result.makeObject(), type: .setattributeresult)
        case .getSubtree(let request):
            let object = Cutaway_Wire_GetSubtreeT()
            object.rootId = request.rootID
            return Cutaway_Wire_BodyUnion(object, type: .getsubtree)
        case .getEnvironment:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetEnvironmentT(), type: .getenvironment)
        case .setEnvironment(let request):
            let object = Cutaway_Wire_SetEnvironmentT()
            object.overrides = request.overrides.makeObject()
            return Cutaway_Wire_BodyUnion(object, type: .setenvironment)
        case .environment(let environment):
            return Cutaway_Wire_BodyUnion(environment.makeObject(), type: .environment)
        }
    }
}

extension Frame {
    func makeObject() -> Cutaway_Wire_FrameT {
        let object = Cutaway_Wire_FrameT()
        object.requestId = requestID
        object.body = body?.makeUnion()
        return object
    }
}

// MARK: - Layout (protocol 0.4)

extension LayoutAttribute {
    var wire: Cutaway_Wire_LayoutAttribute {
        // Every case has a counterpart with the same raw value.
        Cutaway_Wire_LayoutAttribute(rawValue: rawValue) ?? .notanattribute
    }
}

extension LayoutRelation {
    var wire: Cutaway_Wire_LayoutRelation {
        switch self {
        case .equal: return .equal
        case .lessThanOrEqual: return .lessthanorequal
        case .greaterThanOrEqual: return .greaterthanorequal
        }
    }
}

extension ConstraintStatus {
    var wire: Cutaway_Wire_ConstraintStatus {
        switch self {
        case .unknown: return .unknown
        case .satisfied: return .satisfied
        case .unsatisfied: return .unsatisfied
        }
    }
}

extension LayoutItem {
    func makeObject() -> Cutaway_Wire_LayoutItemT {
        let object = Cutaway_Wire_LayoutItemT()
        object.guideFrame = nil
        switch self {
        case .view(let layerID):
            object.kind = .view
            object.layerId = layerID
        case .layoutGuide(let guide):
            object.kind = .layoutguide
            object.layerId = guide.ownerLayerID
            object.guideId = guide.guideID
            object.className = guide.className
            object.displayClassName = guide.displayClassName
            object.identifier = guide.identifier
            object.guideFrame = guide.frame?.wire
            object.guideKind = guide.kind.wire
        case .other(let className, let displayClassName):
            object.kind = .other
            object.className = className
            object.displayClassName = displayClassName
        }
        return object
    }
}

extension LayoutConstraint {
    func makeObject() -> Cutaway_Wire_LayoutConstraintT {
        let object = Cutaway_Wire_LayoutConstraintT()
        object.id = id
        object.className = className
        object.identifier = identifier
        object.firstItem = firstItem?.makeObject()
        object.firstAttribute = firstAttribute.wire
        object.relation = relation.wire
        object.secondItem = secondItem?.makeObject()
        object.secondAttribute = secondAttribute.wire
        object.multiplier = multiplier
        object.constant = constant
        object.priority = priority
        object.status = status.wire
        object.origin = origin.wire
        return object
    }
}

extension LayoutGuideKind {
    var wire: Cutaway_Wire_LayoutGuideKind {
        switch self {
        case .unknown: return .unknown
        case .other: return .other
        case .safeArea: return .safearea
        case .layoutMargins: return .layoutmargins
        case .readableContent: return .readablecontent
        case .keyboard: return .keyboard
        }
    }
}

// MARK: - Environment (protocol 1.2)

extension Traits {
    /// Nil when no trait is set: an absent table means the same (P-ENV-01, P-ENV-02), and it
    /// is what the fixtures write.
    func makeObject() -> Cutaway_Wire_TraitsT? {
        guard self != .unspecified else { return nil }
        let object = Cutaway_Wire_TraitsT()
        object.userInterfaceStyle = userInterfaceStyle.wire
        object.contentSizeCategory = contentSizeCategory.wire
        object.layoutDirection = layoutDirection.wire
        object.horizontalSizeClass = horizontalSizeClass.wire
        object.verticalSizeClass = verticalSizeClass.wire
        return object
    }
}

extension UserInterfaceStyle {
    var wire: Cutaway_Wire_UserInterfaceStyle {
        switch self {
        case .unspecified: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension ContentSizeCategory {
    var wire: Cutaway_Wire_ContentSizeCategory {
        switch self {
        case .unspecified: return .unspecified
        case .extraSmall: return .extrasmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extralarge
        case .extraExtraLarge: return .extraextralarge
        case .extraExtraExtraLarge: return .extraextraextralarge
        case .accessibilityMedium: return .accessibilitymedium
        case .accessibilityLarge: return .accessibilitylarge
        case .accessibilityExtraLarge: return .accessibilityextralarge
        case .accessibilityExtraExtraLarge: return .accessibilityextraextralarge
        case .accessibilityExtraExtraExtraLarge: return .accessibilityextraextraextralarge
        }
    }
}

extension LayoutDirection {
    var wire: Cutaway_Wire_LayoutDirection {
        switch self {
        case .unspecified: return .unspecified
        case .leftToRight: return .lefttoright
        case .rightToLeft: return .righttoleft
        }
    }
}

extension SizeClass {
    var wire: Cutaway_Wire_SizeClass {
        switch self {
        case .unspecified: return .unspecified
        case .compact: return .compact
        case .regular: return .regular
        }
    }
}

extension TraitKind {
    var wire: Cutaway_Wire_TraitKind {
        switch self {
        case .userInterfaceStyle: return .userinterfacestyle
        case .contentSizeCategory: return .contentsizecategory
        case .layoutDirection: return .layoutdirection
        case .horizontalSizeClass: return .horizontalsizeclass
        case .verticalSizeClass: return .verticalsizeclass
        }
    }
}

extension Environment {
    func makeObject() -> Cutaway_Wire_EnvironmentT {
        let object = Cutaway_Wire_EnvironmentT()
        object.overrides = overrides.makeObject()
        object.current = current.makeObject()
        object.overridable = overridable.map(\.wire)
        return object
    }
}
