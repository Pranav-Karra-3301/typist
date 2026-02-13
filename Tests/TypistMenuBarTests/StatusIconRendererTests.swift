import AppKit
import XCTest
@testable import TypistMenuBar

final class StatusIconRendererTests: XCTestCase {
    func testImagesAreProducedForEveryStyle() {
        for style in StatusIconStyle.allCases {
            let image = StatusIconRenderer.image(for: style)
            XCTAssertNotNil(image, "Expected image for style \(style.rawValue)")
            XCTAssertEqual(image?.size.width, 16)
            XCTAssertEqual(image?.size.height, 16)
        }
    }

    func testMonochromeIconsRespectTemplateMode() {
        let templatedImage = StatusIconRenderer.monochromeIcon(for: .dynamic, size: 18, isTemplate: true)
        let normalImage = StatusIconRenderer.monochromeIcon(for: .dynamic, size: 18, isTemplate: false)

        XCTAssertNotNil(templatedImage)
        XCTAssertNotNil(normalImage)
        XCTAssertTrue(templatedImage?.isTemplate == true)
        XCTAssertFalse(normalImage?.isTemplate == true)
    }
}
