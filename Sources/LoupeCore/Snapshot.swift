import Foundation

public enum LoupeNodeKind: String, Codable, Equatable {
    case application
    case scene
    case window
    case view
}

public struct LoupeStyle: Codable, Equatable {
    public var alpha: Double?
    public var backgroundColor: LoupeColor?
    public var cornerRadius: Double?
    public var fontName: String?
    public var fontSize: Double?
    public var textColor: LoupeColor?
    public var borderColor: LoupeColor?
    public var borderWidth: Double?

    public init(
        alpha: Double? = nil,
        backgroundColor: LoupeColor? = nil,
        cornerRadius: Double? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        textColor: LoupeColor? = nil,
        borderColor: LoupeColor? = nil,
        borderWidth: Double? = nil
    ) {
        self.alpha = alpha
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
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

    public init(
        identifier: String? = nil,
        label: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        traits: [String] = [],
        frame: LoupeRect? = nil,
        activationPoint: LoupePoint? = nil,
        isElement: Bool = false
    ) {
        self.identifier = identifier
        self.label = label
        self.value = value
        self.hint = hint
        self.traits = traits
        self.frame = frame
        self.activationPoint = activationPoint
        self.isElement = isElement
    }
}

public struct LoupeNodeRuntimeProperties: Codable, Equatable {
    public var frameworkBundleIdentifier: String?

    public init(frameworkBundleIdentifier: String? = nil) {
        self.frameworkBundleIdentifier = frameworkBundleIdentifier
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

    public init(textAlignment: String? = nil, borderStyle: String? = nil) {
        self.textAlignment = textAlignment
        self.borderStyle = borderStyle
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
    public var adjustedContentInset: LoupeInsets
    public var isScrollEnabled: Bool
    public var alwaysBounceVertical: Bool
    public var alwaysBounceHorizontal: Bool

    public init(
        contentOffset: LoupePoint,
        contentSize: LoupeSize,
        adjustedContentInset: LoupeInsets,
        isScrollEnabled: Bool,
        alwaysBounceVertical: Bool,
        alwaysBounceHorizontal: Bool
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.adjustedContentInset = adjustedContentInset
        self.isScrollEnabled = isScrollEnabled
        self.alwaysBounceVertical = alwaysBounceVertical
        self.alwaysBounceHorizontal = alwaysBounceHorizontal
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
    public var hugging: LoupeUILayoutPriorities
    public var compressionResistance: LoupeUILayoutPriorities
    public var constraints: [LoupeUILayoutConstraintProperties]
    public var affectingHorizontalConstraints: [LoupeUILayoutConstraintProperties]
    public var affectingVerticalConstraints: [LoupeUILayoutConstraintProperties]

    public init(
        translatesAutoresizingMaskIntoConstraints: Bool,
        hugging: LoupeUILayoutPriorities,
        compressionResistance: LoupeUILayoutPriorities,
        constraints: [LoupeUILayoutConstraintProperties] = [],
        affectingHorizontalConstraints: [LoupeUILayoutConstraintProperties] = [],
        affectingVerticalConstraints: [LoupeUILayoutConstraintProperties] = []
    ) {
        self.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
        self.hugging = hugging
        self.compressionResistance = compressionResistance
        self.constraints = constraints
        self.affectingHorizontalConstraints = affectingHorizontalConstraints
        self.affectingVerticalConstraints = affectingVerticalConstraints
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
    public var imageView: LoupeUIImageViewProperties?
    public var pickerView: LoupeUIPickerViewProperties?
    public var tabBar: LoupeUITabBarProperties?
    public var webView: LoupeWKWebViewProperties?

    public init(
        viewController: String? = nil,
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
        imageView: LoupeUIImageViewProperties? = nil,
        pickerView: LoupeUIPickerViewProperties? = nil,
        tabBar: LoupeUITabBarProperties? = nil,
        webView: LoupeWKWebViewProperties? = nil
    ) {
        self.viewController = viewController
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
        self.imageView = imageView
        self.pickerView = pickerView
        self.tabBar = tabBar
        self.webView = webView
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
    public var uiKit: LoupeUIKitProperties?
    public var custom: [String: LoupeMetadataValue]
    public var children: [String]

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
        uiKit: LoupeUIKitProperties? = nil,
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
        self.uiKit = uiKit
        self.custom = custom
        self.children = children
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
