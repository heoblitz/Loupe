import Foundation
import Testing
@testable import LoupeCore

struct RuntimeTests {
    @Test func snapshotNodeCanCarryUIKitAndAccessibilityProperties() {
        let node = LoupeNode(
            ref: "n1",
            parentRef: nil,
            kind: .view,
            typeName: "UIButton",
            role: "button",
            testID: "checkout.payButton",
            frame: LoupeRect(x: 10, y: 20, width: 100, height: 44),
            isVisible: true,
            isEnabled: true,
            isInteractive: true,
            accessibility: LoupeAccessibility(
                identifier: "checkout.payButton",
                label: "Pay",
                traits: ["button"],
                activationPoint: LoupePoint(x: 60, y: 42),
                isElement: true
            ),
            uiKit: LoupeUIKitProperties(
                className: "UIButton",
                tag: 7,
                alpha: 1,
                isHidden: false,
                isOpaque: false,
                clipsToBounds: true,
                userInteractionEnabled: true,
                gestureRecognizers: [],
                isFirstResponder: false,
                control: LoupeUIControlProperties(
                    controlState: "normal",
                    controlEvents: ["touchUpInside"]
                ),
                label: LoupeUILabelProperties(
                    textAlignment: "center",
                    numberOfLines: 1
                )
            )
        )

        #expect(node.accessibility?.identifier == "checkout.payButton")
        #expect(node.accessibility?.traits == ["button"])
        #expect(node.uiKit?.className == "UIButton")
        #expect(node.uiKit?.control?.controlEvents == ["touchUpInside"])
        #expect(node.uiKit?.label?.textAlignment == "center")
    }

    @Test func snapshotNodeCanCarryExtendedUIKitComponentProperties() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let node = LoupeNode(
            ref: "n2",
            parentRef: nil,
            kind: .view,
            typeName: "UIPickerView",
            role: "pickerView",
            testID: "components.picker",
            isVisible: true,
            isEnabled: true,
            isInteractive: true,
            uiKit: LoupeUIKitProperties(
                className: "UIPickerView",
                tag: 0,
                alpha: 1,
                isHidden: false,
                isOpaque: false,
                clipsToBounds: false,
                userInteractionEnabled: true,
                isFirstResponder: false,
                stepper: LoupeUIStepperProperties(value: 4, stepValue: 2),
                datePicker: LoupeUIDatePickerProperties(mode: "date", date: date),
                pageControl: LoupeUIPageControlProperties(currentPage: 2, numberOfPages: 5),
                progressView: LoupeUIProgressViewProperties(value: 0.65),
                activityIndicator: LoupeUIActivityIndicatorProperties(isAnimating: true, style: "medium"),
                imageView: LoupeUIImageViewProperties(imageSize: LoupeSize(width: 20, height: 20)),
                pickerView: LoupeUIPickerViewProperties(numberOfComponents: 1, selectedRows: [1]),
                tabBar: LoupeUITabBarProperties(items: ["Home", "Search"], selectedItem: "Home"),
                webView: LoupeWKWebViewProperties(
                    url: "https://loupe.local/fixture",
                    title: "Web Fixture"
                )
            )
        )

        #expect(node.uiKit?.stepper?.value == 4)
        #expect(node.uiKit?.stepper?.stepValue == 2)
        #expect(node.uiKit?.datePicker?.mode == "date")
        #expect(node.uiKit?.datePicker?.date == date)
        #expect(node.uiKit?.pageControl?.currentPage == 2)
        #expect(node.uiKit?.pageControl?.numberOfPages == 5)
        #expect(node.uiKit?.progressView?.value == 0.65)
        #expect(node.uiKit?.activityIndicator?.isAnimating == true)
        #expect(node.uiKit?.activityIndicator?.style == "medium")
        #expect(node.uiKit?.imageView?.imageSize == LoupeSize(width: 20, height: 20))
        #expect(node.uiKit?.pickerView?.numberOfComponents == 1)
        #expect(node.uiKit?.pickerView?.selectedRows == [1])
        #expect(node.uiKit?.tabBar?.items == ["Home", "Search"])
        #expect(node.uiKit?.tabBar?.selectedItem == "Home")
        #expect(node.uiKit?.webView?.url == "https://loupe.local/fixture")
        #expect(node.uiKit?.webView?.title == "Web Fixture")
    }

    @Test func snapshotNodeCanCarryLayoutAndStackViewProperties() {
        let node = LoupeNode(
            ref: "stack",
            parentRef: nil,
            kind: .view,
            typeName: "UIStackView",
            testID: "place.actions",
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            uiKit: LoupeUIKitProperties(
                className: "UIStackView",
                tag: 0,
                alpha: 1,
                isHidden: false,
                isOpaque: false,
                clipsToBounds: false,
                userInteractionEnabled: true,
                isFirstResponder: false,
                layout: LoupeUILayoutProperties(
                    translatesAutoresizingMaskIntoConstraints: false,
                    hugging: LoupeUILayoutPriorities(horizontal: 250, vertical: 251),
                    compressionResistance: LoupeUILayoutPriorities(horizontal: 750, vertical: 751),
                    constraints: [
                        LoupeUILayoutConstraintProperties(
                            id: "c-height",
                            identifier: "height",
                            firstItem: "UIStackView#place.actions",
                            firstAttribute: "height",
                            relation: "equal",
                            secondItem: nil,
                            secondAttribute: "notAnAttribute",
                            multiplier: 1,
                            constant: 52,
                            priority: 1000,
                            isActive: true
                        )
                    ]
                ),
                stackView: LoupeUIStackViewProperties(
                    axis: "horizontal",
                    alignment: "fill",
                    distribution: "fillEqually",
                    spacing: 8,
                    isBaselineRelativeArrangement: false,
                    isLayoutMarginsRelativeArrangement: true,
                    arrangedSubviewCount: 3
                )
            )
        )

        #expect(node.uiKit?.layout?.translatesAutoresizingMaskIntoConstraints == false)
        #expect(node.uiKit?.layout?.hugging.horizontal == 250)
        #expect(node.uiKit?.layout?.compressionResistance.vertical == 751)
        #expect(node.uiKit?.layout?.constraints.first?.id == "c-height")
        #expect(node.uiKit?.layout?.constraints.first?.identifier == "height")
        #expect(node.uiKit?.stackView?.axis == "horizontal")
        #expect(node.uiKit?.stackView?.distribution == "fillEqually")
        #expect(node.uiKit?.stackView?.arrangedSubviewCount == 3)
    }
}
