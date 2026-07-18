import Foundation

public enum LoupeNodeKind: String, Codable, Equatable {
    case application
    case scene
    case window
    case view

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "application":
            self = .application
        case "scene":
            self = .scene
        case "window":
            self = .window
        case "view", "tabBarItem":
            self = .view
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize LoupeNodeKind from invalid String value \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct LoupeStyle: Codable, Equatable {
    public var alpha: Double?
    public var backgroundColor: LoupeColor?
    public var tintColor: LoupeColor?
    public var cornerRadius: Double?
    public var fontName: String?
    public var fontSize: Double?
    public var textColor: LoupeColor?
    public var borderColor: LoupeColor?
    public var borderWidth: Double?
    public var shadowColor: LoupeColor?
    public var shadowOpacity: Double?
    public var shadowRadius: Double?
    public var shadowOffset: LoupeSize?

    public init(
        alpha: Double? = nil,
        backgroundColor: LoupeColor? = nil,
        tintColor: LoupeColor? = nil,
        cornerRadius: Double? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        textColor: LoupeColor? = nil,
        borderColor: LoupeColor? = nil,
        borderWidth: Double? = nil,
        shadowColor: LoupeColor? = nil,
        shadowOpacity: Double? = nil,
        shadowRadius: Double? = nil,
        shadowOffset: LoupeSize? = nil
    ) {
        self.alpha = alpha
        self.backgroundColor = backgroundColor
        self.tintColor = tintColor
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowOffset = shadowOffset
    }
}

public struct LoupeAccessibility: Codable, Equatable {
    public var identifier: String?
    public var label: String?
    public var value: String?
    public var hint: String?
    public var traits: [String]
    public var frame: LoupeRect?
    public var activationPoint: LoupePoint?
    public var isElement: Bool
    public var actions: [LoupeAccessibilityAction]?

    public init(
        identifier: String? = nil,
        label: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        traits: [String] = [],
        frame: LoupeRect? = nil,
        activationPoint: LoupePoint? = nil,
        isElement: Bool = false,
        actions: [LoupeAccessibilityAction]? = nil
    ) {
        self.identifier = identifier
        self.label = label
        self.value = value
        self.hint = hint
        self.traits = traits
        self.frame = frame
        self.activationPoint = activationPoint
        self.isElement = isElement
        self.actions = actions
    }
}

public struct LoupeNodeRuntimeProperties: Codable, Equatable {
    public var frameworkBundleIdentifier: String?

    public init(frameworkBundleIdentifier: String? = nil) {
        self.frameworkBundleIdentifier = frameworkBundleIdentifier
    }
}

public struct LoupeSwiftUIProperty: Codable, Equatable {
    public var name: String
    public var typeName: String
    public var value: LoupeMetadataValue?
    public var evidence: [String]

    public init(
        name: String,
        typeName: String,
        value: LoupeMetadataValue? = nil,
        evidence: [String] = []
    ) {
        self.name = name
        self.typeName = typeName
        self.value = value
        self.evidence = evidence
    }
}

public struct LoupeSwiftUIProperties: Codable, Equatable {
    public var origin: String
    public var backingTypeName: String
    public var viewController: String?
    public var rootTypeName: String?
    public var properties: [LoupeSwiftUIProperty]
    public var evidence: [String]

    public init(
        origin: String,
        backingTypeName: String,
        viewController: String? = nil,
        rootTypeName: String? = nil,
        properties: [LoupeSwiftUIProperty] = [],
        evidence: [String] = []
    ) {
        self.origin = origin
        self.backingTypeName = backingTypeName
        self.viewController = viewController
        self.rootTypeName = rootTypeName
        self.properties = properties
        self.evidence = evidence
    }
}

public struct LoupeUIControlProperties: Codable, Equatable {
    public var controlState: String?
    public var controlEvents: [String]

    public init(controlState: String? = nil, controlEvents: [String] = []) {
        self.controlState = controlState
        self.controlEvents = controlEvents
    }
}

public struct LoupeUILabelProperties: Codable, Equatable {
    public var textAlignment: String?
    public var numberOfLines: Int?
    public var lineBreakMode: String?

    public init(textAlignment: String? = nil, numberOfLines: Int? = nil, lineBreakMode: String? = nil) {
        self.textAlignment = textAlignment
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
    }
}

public struct LoupeUIButtonProperties: Codable, Equatable {
    public var lineBreakMode: String?

    public init(lineBreakMode: String? = nil) {
        self.lineBreakMode = lineBreakMode
    }
}

public struct LoupeUITextFieldProperties: Codable, Equatable {
    public var textAlignment: String?
    public var borderStyle: String?
    public var isSecureTextEntry: Bool?

    public init(textAlignment: String? = nil, borderStyle: String? = nil, isSecureTextEntry: Bool? = nil) {
        self.textAlignment = textAlignment
        self.borderStyle = borderStyle
        self.isSecureTextEntry = isSecureTextEntry
    }
}

public struct LoupeUITextViewProperties: Codable, Equatable {
    public var textAlignment: String?

    public init(textAlignment: String? = nil) {
        self.textAlignment = textAlignment
    }
}

public struct LoupeUIScrollViewProperties: Codable, Equatable {
    public var contentOffset: LoupePoint
    public var contentSize: LoupeSize
    public var contentInset: LoupeInsets
    public var adjustedContentInset: LoupeInsets
    public var scrollIndicatorInsets: LoupeInsets
    public var isScrollEnabled: Bool
    public var isPagingEnabled: Bool
    public var bounces: Bool
    public var alwaysBounceVertical: Bool
    public var alwaysBounceHorizontal: Bool
    public var showsVerticalScrollIndicator: Bool
    public var showsHorizontalScrollIndicator: Bool

    private enum CodingKeys: String, CodingKey {
        case contentOffset
        case contentSize
        case contentInset
        case adjustedContentInset
        case scrollIndicatorInsets
        case isScrollEnabled
        case isPagingEnabled
        case bounces
        case alwaysBounceVertical
        case alwaysBounceHorizontal
        case showsVerticalScrollIndicator
        case showsHorizontalScrollIndicator
    }

    public init(
        contentOffset: LoupePoint,
        contentSize: LoupeSize,
        contentInset: LoupeInsets = LoupeInsets(top: 0, left: 0, bottom: 0, right: 0),
        adjustedContentInset: LoupeInsets,
        scrollIndicatorInsets: LoupeInsets = LoupeInsets(top: 0, left: 0, bottom: 0, right: 0),
        isScrollEnabled: Bool,
        isPagingEnabled: Bool = false,
        bounces: Bool = true,
        alwaysBounceVertical: Bool,
        alwaysBounceHorizontal: Bool,
        showsVerticalScrollIndicator: Bool = true,
        showsHorizontalScrollIndicator: Bool = true
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInset = contentInset
        self.adjustedContentInset = adjustedContentInset
        self.scrollIndicatorInsets = scrollIndicatorInsets
        self.isScrollEnabled = isScrollEnabled
        self.isPagingEnabled = isPagingEnabled
        self.bounces = bounces
        self.alwaysBounceVertical = alwaysBounceVertical
        self.alwaysBounceHorizontal = alwaysBounceHorizontal
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentOffset = try container.decode(LoupePoint.self, forKey: .contentOffset)
        contentSize = try container.decode(LoupeSize.self, forKey: .contentSize)
        contentInset = try container.decodeIfPresent(LoupeInsets.self, forKey: .contentInset)
            ?? LoupeInsets(top: 0, left: 0, bottom: 0, right: 0)
        adjustedContentInset = try container.decodeIfPresent(LoupeInsets.self, forKey: .adjustedContentInset)
            ?? LoupeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollIndicatorInsets = try container.decodeIfPresent(LoupeInsets.self, forKey: .scrollIndicatorInsets)
            ?? LoupeInsets(top: 0, left: 0, bottom: 0, right: 0)
        isScrollEnabled = try container.decode(Bool.self, forKey: .isScrollEnabled)
        isPagingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPagingEnabled) ?? false
        bounces = try container.decodeIfPresent(Bool.self, forKey: .bounces) ?? true
        alwaysBounceVertical = try container.decodeIfPresent(Bool.self, forKey: .alwaysBounceVertical) ?? false
        alwaysBounceHorizontal = try container.decodeIfPresent(Bool.self, forKey: .alwaysBounceHorizontal) ?? false
        showsVerticalScrollIndicator = try container.decodeIfPresent(Bool.self, forKey: .showsVerticalScrollIndicator) ?? true
        showsHorizontalScrollIndicator = try container.decodeIfPresent(Bool.self, forKey: .showsHorizontalScrollIndicator) ?? true
    }
}

public struct LoupeUISwitchProperties: Codable, Equatable {
    public var isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }
}

public struct LoupeUISliderProperties: Codable, Equatable {
    public var value: Double?
    public var minimumValue: Double?
    public var maximumValue: Double?

    public init(value: Double? = nil, minimumValue: Double? = nil, maximumValue: Double? = nil) {
        self.value = value
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
    }
}

public struct LoupeUIStepperProperties: Codable, Equatable {
    public var value: Double?
    public var minimumValue: Double?
    public var maximumValue: Double?
    public var stepValue: Double?

    public init(
        value: Double? = nil,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        stepValue: Double? = nil
    ) {
        self.value = value
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.stepValue = stepValue
    }
}

public struct LoupeUISegmentedControlProperties: Codable, Equatable {
    public var selectedSegmentIndex: Int?
    public var segments: [String]

    public init(selectedSegmentIndex: Int? = nil, segments: [String] = []) {
        self.selectedSegmentIndex = selectedSegmentIndex
        self.segments = segments
    }
}

public struct LoupeUIDatePickerProperties: Codable, Equatable {
    public var mode: String?
    public var date: Date?
    public var minimumDate: Date?
    public var maximumDate: Date?

    public init(mode: String? = nil, date: Date? = nil, minimumDate: Date? = nil, maximumDate: Date? = nil) {
        self.mode = mode
        self.date = date
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
    }
}

public struct LoupeUIPageControlProperties: Codable, Equatable {
    public var currentPage: Int?
    public var numberOfPages: Int?

    public init(currentPage: Int? = nil, numberOfPages: Int? = nil) {
        self.currentPage = currentPage
        self.numberOfPages = numberOfPages
    }
}

public struct LoupeUIProgressViewProperties: Codable, Equatable {
    public var value: Double?

    public init(value: Double? = nil) {
        self.value = value
    }
}

public struct LoupeUIActivityIndicatorProperties: Codable, Equatable {
    public var isAnimating: Bool?
    public var style: String?

    public init(isAnimating: Bool? = nil, style: String? = nil) {
        self.isAnimating = isAnimating
        self.style = style
    }
}

public struct LoupeUICollectionFlowLayoutProperties: Codable, Equatable {
    public var itemSize: LoupeSize
    public var estimatedItemSize: LoupeSize
    public var usesEstimatedItemSize: Bool
    public var usesAutomaticItemSize: Bool

    public init(
        itemSize: LoupeSize,
        estimatedItemSize: LoupeSize,
        usesEstimatedItemSize: Bool,
        usesAutomaticItemSize: Bool
    ) {
        self.itemSize = itemSize
        self.estimatedItemSize = estimatedItemSize
        self.usesEstimatedItemSize = usesEstimatedItemSize
        self.usesAutomaticItemSize = usesAutomaticItemSize
    }
}

public struct LoupeUICollectionViewProperties: Codable, Equatable {
    public var selfSizingInvalidation: String?
    public var layoutClassName: String
    public var delegateRespondsToSizeForItemAt: Bool
    public var flowLayout: LoupeUICollectionFlowLayoutProperties?

    public init(
        selfSizingInvalidation: String? = nil,
        layoutClassName: String,
        delegateRespondsToSizeForItemAt: Bool,
        flowLayout: LoupeUICollectionFlowLayoutProperties? = nil
    ) {
        self.selfSizingInvalidation = selfSizingInvalidation
        self.layoutClassName = layoutClassName
        self.delegateRespondsToSizeForItemAt = delegateRespondsToSizeForItemAt
        self.flowLayout = flowLayout
    }
}

public struct LoupeUITableViewProperties: Codable, Equatable {
    public var selfSizingInvalidation: String?
    public var rowHeight: Double
    public var estimatedRowHeight: Double
    public var usesAutomaticRowHeight: Bool
    public var usesEstimatedRowHeight: Bool
    public var delegateRespondsToHeightForRowAt: Bool
    public var delegateRespondsToEstimatedHeightForRowAt: Bool

    public init(
        selfSizingInvalidation: String? = nil,
        rowHeight: Double,
        estimatedRowHeight: Double,
        usesAutomaticRowHeight: Bool,
        usesEstimatedRowHeight: Bool,
        delegateRespondsToHeightForRowAt: Bool,
        delegateRespondsToEstimatedHeightForRowAt: Bool
    ) {
        self.selfSizingInvalidation = selfSizingInvalidation
        self.rowHeight = rowHeight
        self.estimatedRowHeight = estimatedRowHeight
        self.usesAutomaticRowHeight = usesAutomaticRowHeight
        self.usesEstimatedRowHeight = usesEstimatedRowHeight
        self.delegateRespondsToHeightForRowAt = delegateRespondsToHeightForRowAt
        self.delegateRespondsToEstimatedHeightForRowAt = delegateRespondsToEstimatedHeightForRowAt
    }
}

public struct LoupeUIImageViewProperties: Codable, Equatable {
    public var imageSize: LoupeSize?

    public init(imageSize: LoupeSize? = nil) {
        self.imageSize = imageSize
    }
}

public struct LoupeUIPickerViewProperties: Codable, Equatable {
    public var numberOfComponents: Int?
    public var selectedRows: [Int]

    public init(numberOfComponents: Int? = nil, selectedRows: [Int] = []) {
        self.numberOfComponents = numberOfComponents
        self.selectedRows = selectedRows
    }
}

public struct LoupeUITabBarProperties: Codable, Equatable {
    public var items: [String]
    public var selectedItem: String?

    public init(items: [String] = [], selectedItem: String? = nil) {
        self.items = items
        self.selectedItem = selectedItem
    }
}

public struct LoupeWKWebViewProperties: Codable, Equatable {
    public var url: String?
    public var title: String?

    public init(url: String? = nil, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

public struct LoupeUILayoutPriorities: Codable, Equatable {
    public var horizontal: Double
    public var vertical: Double

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public struct LoupeUILayoutConstraintProperties: Codable, Equatable {
    public var id: String
    public var identifier: String?
    public var firstItem: String?
    public var firstAttribute: String
    public var relation: String
    public var secondItem: String?
    public var secondAttribute: String
    public var multiplier: Double
    public var constant: Double
    public var priority: Double
    public var isActive: Bool

    public init(
        id: String = "",
        identifier: String? = nil,
        firstItem: String? = nil,
        firstAttribute: String,
        relation: String,
        secondItem: String? = nil,
        secondAttribute: String,
        multiplier: Double,
        constant: Double,
        priority: Double,
        isActive: Bool
    ) {
        self.id = id
        self.identifier = identifier
        self.firstItem = firstItem
        self.firstAttribute = firstAttribute
        self.relation = relation
        self.secondItem = secondItem
        self.secondAttribute = secondAttribute
        self.multiplier = multiplier
        self.constant = constant
        self.priority = priority
        self.isActive = isActive
    }
}

public struct LoupeUILayoutProperties: Codable, Equatable {
    public var translatesAutoresizingMaskIntoConstraints: Bool
    public var isAmbiguousLayout: Bool
    public var hugging: LoupeUILayoutPriorities
    public var compressionResistance: LoupeUILayoutPriorities
    public var constraints: [LoupeUILayoutConstraintProperties]
    public var affectingHorizontalConstraints: [LoupeUILayoutConstraintProperties]
    public var affectingVerticalConstraints: [LoupeUILayoutConstraintProperties]

    public init(
        translatesAutoresizingMaskIntoConstraints: Bool,
        isAmbiguousLayout: Bool = false,
        hugging: LoupeUILayoutPriorities,
        compressionResistance: LoupeUILayoutPriorities,
        constraints: [LoupeUILayoutConstraintProperties] = [],
        affectingHorizontalConstraints: [LoupeUILayoutConstraintProperties] = [],
        affectingVerticalConstraints: [LoupeUILayoutConstraintProperties] = []
    ) {
        self.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
        self.isAmbiguousLayout = isAmbiguousLayout
        self.hugging = hugging
        self.compressionResistance = compressionResistance
        self.constraints = constraints
        self.affectingHorizontalConstraints = affectingHorizontalConstraints
        self.affectingVerticalConstraints = affectingVerticalConstraints
    }

    private enum CodingKeys: String, CodingKey {
        case translatesAutoresizingMaskIntoConstraints
        case isAmbiguousLayout
        case hugging
        case compressionResistance
        case constraints
        case affectingHorizontalConstraints
        case affectingVerticalConstraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translatesAutoresizingMaskIntoConstraints = try container.decode(Bool.self, forKey: .translatesAutoresizingMaskIntoConstraints)
        isAmbiguousLayout = try container.decodeIfPresent(Bool.self, forKey: .isAmbiguousLayout) ?? false
        hugging = try container.decode(LoupeUILayoutPriorities.self, forKey: .hugging)
        compressionResistance = try container.decode(LoupeUILayoutPriorities.self, forKey: .compressionResistance)
        constraints = try container.decodeIfPresent([LoupeUILayoutConstraintProperties].self, forKey: .constraints) ?? []
        affectingHorizontalConstraints = try container.decodeIfPresent([LoupeUILayoutConstraintProperties].self, forKey: .affectingHorizontalConstraints) ?? []
        affectingVerticalConstraints = try container.decodeIfPresent([LoupeUILayoutConstraintProperties].self, forKey: .affectingVerticalConstraints) ?? []
    }
}

public struct LoupeUIStackViewProperties: Codable, Equatable {
    public var axis: String
    public var alignment: String
    public var distribution: String
    public var spacing: Double
    public var isBaselineRelativeArrangement: Bool
    public var isLayoutMarginsRelativeArrangement: Bool
    public var arrangedSubviewCount: Int

    public init(
        axis: String,
        alignment: String,
        distribution: String,
        spacing: Double,
        isBaselineRelativeArrangement: Bool,
        isLayoutMarginsRelativeArrangement: Bool,
        arrangedSubviewCount: Int
    ) {
        self.axis = axis
        self.alignment = alignment
        self.distribution = distribution
        self.spacing = spacing
        self.isBaselineRelativeArrangement = isBaselineRelativeArrangement
        self.isLayoutMarginsRelativeArrangement = isLayoutMarginsRelativeArrangement
        self.arrangedSubviewCount = arrangedSubviewCount
    }
}

public struct LoupeUIKitProperties: Codable, Equatable {
    public var viewController: String?
    public var viewControllerRole: String?
    public var className: String
    public var tag: Int
    public var alpha: Double
    public var isHidden: Bool
    public var isOpaque: Bool
    public var clipsToBounds: Bool
    public var contentMode: String?
    public var userInteractionEnabled: Bool
    public var gestureRecognizers: [String]
    public var isFirstResponder: Bool
    public var isFocused: Bool?
    public var canBecomeFocused: Bool?
    public var windowLevel: Double?
    public var layout: LoupeUILayoutProperties?
    public var stackView: LoupeUIStackViewProperties?
    public var control: LoupeUIControlProperties?
    public var label: LoupeUILabelProperties?
    public var button: LoupeUIButtonProperties?
    public var textField: LoupeUITextFieldProperties?
    public var textView: LoupeUITextViewProperties?
    public var scrollView: LoupeUIScrollViewProperties?
    public var switchControl: LoupeUISwitchProperties?
    public var slider: LoupeUISliderProperties?
    public var stepper: LoupeUIStepperProperties?
    public var segmentedControl: LoupeUISegmentedControlProperties?
    public var datePicker: LoupeUIDatePickerProperties?
    public var pageControl: LoupeUIPageControlProperties?
    public var progressView: LoupeUIProgressViewProperties?
    public var activityIndicator: LoupeUIActivityIndicatorProperties?
    public var collectionView: LoupeUICollectionViewProperties?
    public var tableView: LoupeUITableViewProperties?
    public var imageView: LoupeUIImageViewProperties?
    public var pickerView: LoupeUIPickerViewProperties?
    public var tabBar: LoupeUITabBarProperties?
    public var webView: LoupeWKWebViewProperties?

    public init(
        viewController: String? = nil,
        viewControllerRole: String? = nil,
        className: String,
        tag: Int,
        alpha: Double,
        isHidden: Bool,
        isOpaque: Bool,
        clipsToBounds: Bool,
        contentMode: String? = nil,
        userInteractionEnabled: Bool,
        gestureRecognizers: [String] = [],
        isFirstResponder: Bool,
        isFocused: Bool? = nil,
        canBecomeFocused: Bool? = nil,
        windowLevel: Double? = nil,
        layout: LoupeUILayoutProperties? = nil,
        stackView: LoupeUIStackViewProperties? = nil,
        control: LoupeUIControlProperties? = nil,
        label: LoupeUILabelProperties? = nil,
        button: LoupeUIButtonProperties? = nil,
        textField: LoupeUITextFieldProperties? = nil,
        textView: LoupeUITextViewProperties? = nil,
        scrollView: LoupeUIScrollViewProperties? = nil,
        switchControl: LoupeUISwitchProperties? = nil,
        slider: LoupeUISliderProperties? = nil,
        stepper: LoupeUIStepperProperties? = nil,
        segmentedControl: LoupeUISegmentedControlProperties? = nil,
        datePicker: LoupeUIDatePickerProperties? = nil,
        pageControl: LoupeUIPageControlProperties? = nil,
        progressView: LoupeUIProgressViewProperties? = nil,
        activityIndicator: LoupeUIActivityIndicatorProperties? = nil,
        collectionView: LoupeUICollectionViewProperties? = nil,
        tableView: LoupeUITableViewProperties? = nil,
        imageView: LoupeUIImageViewProperties? = nil,
        pickerView: LoupeUIPickerViewProperties? = nil,
        tabBar: LoupeUITabBarProperties? = nil,
        webView: LoupeWKWebViewProperties? = nil
    ) {
        self.viewController = viewController
        self.viewControllerRole = viewControllerRole
        self.className = className
        self.tag = tag
        self.alpha = alpha
        self.isHidden = isHidden
        self.isOpaque = isOpaque
        self.clipsToBounds = clipsToBounds
        self.contentMode = contentMode
        self.userInteractionEnabled = userInteractionEnabled
        self.gestureRecognizers = gestureRecognizers
        self.isFirstResponder = isFirstResponder
        self.isFocused = isFocused
        self.canBecomeFocused = canBecomeFocused
        self.windowLevel = windowLevel
        self.layout = layout
        self.stackView = stackView
        self.control = control
        self.label = label
        self.button = button
        self.textField = textField
        self.textView = textView
        self.scrollView = scrollView
        self.switchControl = switchControl
        self.slider = slider
        self.stepper = stepper
        self.segmentedControl = segmentedControl
        self.datePicker = datePicker
        self.pageControl = pageControl
        self.progressView = progressView
        self.activityIndicator = activityIndicator
        self.collectionView = collectionView
        self.tableView = tableView
        self.imageView = imageView
        self.pickerView = pickerView
        self.tabBar = tabBar
        self.webView = webView
    }
}

@dynamicMemberLookup
public struct LoupeAppKitProperties: Codable, Equatable {
    private var storage: LoupeUIKitProperties

    public init(storage: LoupeUIKitProperties) {
        self.storage = storage
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<LoupeUIKitProperties, Value>) -> Value {
        storage[keyPath: keyPath]
    }

    public init(from decoder: Decoder) throws {
        storage = try LoupeUIKitProperties(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }

    public var commonViewProperties: LoupeUIKitProperties {
        storage
    }
}

public struct LoupeNode: Codable, Equatable {
    public var ref: String
    public var parentRef: String?
    public var kind: LoupeNodeKind
    public var typeName: String
    public var role: String?
    public var testID: String?
    public var label: String?
    public var value: String?
    public var placeholder: String?
    public var text: String?
    public var renderedText: String?
    public var semanticText: String?
    public var frame: LoupeRect?
    public var isVisible: Bool
    public var isEnabled: Bool
    public var isInteractive: Bool
    public var style: LoupeStyle?
    public var accessibility: LoupeAccessibility?
    public var runtime: LoupeNodeRuntimeProperties?
    public var uikit: LoupeUIKitProperties?
    public var appkit: LoupeAppKitProperties?
    public var swiftui: LoupeSwiftUIProperties?
    public var custom: [String: LoupeMetadataValue]
    public var children: [String]

    public var platform: LoupeUIKitProperties? {
        uikit ?? appkit?.commonViewProperties
    }

    private enum CodingKeys: String, CodingKey {
        case ref
        case parentRef
        case kind
        case typeName
        case role
        case testID
        case label
        case value
        case placeholder
        case text
        case renderedText
        case semanticText
        case frame
        case isVisible
        case isEnabled
        case isInteractive
        case style
        case accessibility
        case runtime
        case uikit
        case appkit
        case swiftui
        case custom
        case children
    }

    public init(
        ref: String,
        parentRef: String?,
        kind: LoupeNodeKind,
        typeName: String,
        role: String? = nil,
        testID: String? = nil,
        label: String? = nil,
        value: String? = nil,
        placeholder: String? = nil,
        text: String? = nil,
        renderedText: String? = nil,
        semanticText: String? = nil,
        frame: LoupeRect? = nil,
        isVisible: Bool,
        isEnabled: Bool,
        isInteractive: Bool,
        style: LoupeStyle? = nil,
        accessibility: LoupeAccessibility? = nil,
        runtime: LoupeNodeRuntimeProperties? = nil,
        uikit: LoupeUIKitProperties? = nil,
        appkit: LoupeAppKitProperties? = nil,
        swiftui: LoupeSwiftUIProperties? = nil,
        custom: [String: LoupeMetadataValue] = [:],
        children: [String] = []
    ) {
        self.ref = ref
        self.parentRef = parentRef
        self.kind = kind
        self.typeName = typeName
        self.role = role
        self.testID = testID
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.text = text
        self.renderedText = renderedText
        self.semanticText = semanticText
        self.frame = frame
        self.isVisible = isVisible
        self.isEnabled = isEnabled
        self.isInteractive = isInteractive
        self.style = style
        self.accessibility = accessibility
        self.runtime = runtime
        self.uikit = uikit
        self.appkit = appkit
        self.swiftui = swiftui
        self.custom = custom
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        ref = try container.decode(String.self, forKey: .ref)
        parentRef = try container.decodeIfPresent(String.self, forKey: .parentRef)
        kind = try container.decode(LoupeNodeKind.self, forKey: .kind)
        typeName = try container.decode(String.self, forKey: .typeName)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        testID = try container.decodeIfPresent(String.self, forKey: .testID)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        renderedText = try container.decodeIfPresent(String.self, forKey: .renderedText)
        semanticText = try container.decodeIfPresent(String.self, forKey: .semanticText)
        frame = try container.decodeIfPresent(LoupeRect.self, forKey: .frame)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isInteractive = try container.decode(Bool.self, forKey: .isInteractive)
        style = try container.decodeIfPresent(LoupeStyle.self, forKey: .style)
        accessibility = try container.decodeIfPresent(LoupeAccessibility.self, forKey: .accessibility)
        runtime = try container.decodeIfPresent(LoupeNodeRuntimeProperties.self, forKey: .runtime)
        uikit = try container.decodeIfPresent(LoupeUIKitProperties.self, forKey: .uikit)
        appkit = try container.decodeIfPresent(LoupeAppKitProperties.self, forKey: .appkit)
        swiftui = try container.decodeIfPresent(LoupeSwiftUIProperties.self, forKey: .swiftui)
        custom = try container.decodeIfPresent([String: LoupeMetadataValue].self, forKey: .custom) ?? [:]
        children = try container.decodeIfPresent([String].self, forKey: .children) ?? []
    }
}

extension LoupeNode {
    public var isLoupeProbeMarker: Bool {
        hasLoupeProbeMetadata || hasLoupeProbeTypeName || isAppAuthoredLoupeProbeControl
    }

    var hasLoupeProbeMetadata: Bool {
        custom["loupe.probe"] == .bool(true)
    }

    var hasLoupeProbeTypeName: Bool {
        if typeName == "LoupeWatchProbe" {
            return true
        }
        let lowercasedType = typeName.lowercased()
        if lowercasedType.contains("loupeprobe") {
            return true
        }
        return lowercasedType.contains("platformviewrepresentableadaptor<")
            && lowercasedType.contains("probe")
    }

    var isAppAuthoredLoupeProbeControl: Bool {
        let lowercasedType = typeName.lowercased()
        guard lowercasedType == "probecontrol" || lowercasedType.hasSuffix(".probecontrol") else {
            return false
        }
        let identifiers = [testID, accessibility?.identifier]
            .compactMap { $0?.lowercased() }
        return identifiers.contains { identifier in
            identifier.hasPrefix("probe_")
                || identifier.hasPrefix("probe.")
                || identifier.contains(".probe.")
                || identifier.hasSuffix(".probe")
        }
    }
}

public struct LoupeScreen: Codable, Equatable {
    public var size: LoupeSize
    public var scale: Double
    public var interfaceStyle: String?

    public init(size: LoupeSize, scale: Double, interfaceStyle: String? = nil) {
        self.size = size
        self.scale = scale
        self.interfaceStyle = interfaceStyle
    }
}

public struct LoupeSnapshot: Codable, Equatable {
    public var id: String
    public var capturedAt: Date
    public var screen: LoupeScreen
    public var rootRefs: [String]
    public var nodes: [String: LoupeNode]

    public init(
        id: String,
        capturedAt: Date,
        screen: LoupeScreen,
        rootRefs: [String],
        nodes: [String: LoupeNode]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.screen = screen
        self.rootRefs = rootRefs
        self.nodes = nodes
    }
}
