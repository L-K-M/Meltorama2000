import XCTest
@testable import MeltoramaCore

final class CropTests: XCTestCase {
    func testDecimalCropKeepsAndroidRoundedDimensions() throws {
        let crop = CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9)
        let large = try crop.pixelRect(width: 1200, height: 900)
        XCTAssertEqual([large.x, large.y, large.width, large.height], [120, 90, 960, 720])
        let small = try crop.pixelRect(width: 128, height: 96)
        XCTAssertEqual([small.x, small.y, small.width, small.height], [13, 10, 102, 77])
    }

    func testHalfPixelTiesRoundUpLikeKotlin() throws {
        let rect = try CropRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75).pixelRect(width: 10, height: 10)
        XCTAssertEqual([rect.x, rect.y, rect.width, rect.height], [3, 3, 5, 5])
    }

    func testSliversAndFullFrameStayWithinTheBitmap() throws {
        let crop = CropRect(left: 0.98, top: 0.98, right: 1, bottom: 1)
        for size in [1, 3, 77, 1200] {
            let rect = try crop.pixelRect(width: size, height: size)
            XCTAssertGreaterThanOrEqual(rect.width, 1)
            XCTAssertGreaterThanOrEqual(rect.height, 1)
            XCTAssertGreaterThanOrEqual(rect.x, 0)
            XCTAssertGreaterThanOrEqual(rect.y, 0)
            XCTAssertLessThanOrEqual(rect.x + rect.width, size)
            XCTAssertLessThanOrEqual(rect.y + rect.height, size)
        }
        let full = try CropRect.full.pixelRect(width: 123, height: 77)
        XCTAssertEqual([full.x, full.y, full.width, full.height], [0, 0, 123, 77])
    }

    func testPixelBoundsRejectInvalidCropsAndDimensions() {
        XCTAssertThrowsError(try CropRect.full.pixelRect(width: 0, height: 10))
        XCTAssertThrowsError(try CropRect(left: -0.1, top: 0, right: 1, bottom: 1).pixelRect(width: 10, height: 10))
        XCTAssertThrowsError(try CropRect(left: .nan, top: 0, right: 1, bottom: 1).pixelRect(width: 10, height: 10))
    }
}
