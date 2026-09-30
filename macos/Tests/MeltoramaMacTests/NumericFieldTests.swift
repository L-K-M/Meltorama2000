import Foundation
import XCTest
@testable import MeltoramaMac

final class NumericFieldTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testPartialInputDoesNotChangeValueUntilCommit() {
        var value: Float = 0.8
        var editor = NumericEditingBuffer(value: value, locale: english)
        for partial in ["", "0", "0.", "0.4", "0.45"] {
            editor.replaceText(partial)
            XCTAssertEqual(value, 0.8)
            XCTAssertEqual(editor.text, partial)
        }
        value = editor.commit(currentValue: value, range: 0.05...1, locale: english)
        XCTAssertEqual(value, 0.45, accuracy: 0.000001)
        XCTAssertEqual(editor.text, "0.45")
    }

    func testCommitAcceptsNegativeAndClampsOnlyCompleteValue() {
        var editor = NumericEditingBuffer(value: 0, locale: english)
        editor.replaceText("-0.45")
        XCTAssertEqual(editor.commit(currentValue: 0, range: -1...1, locale: english), -0.45, accuracy: 0.000001)
        editor.replaceText("-20")
        XCTAssertEqual(editor.commit(currentValue: 0, range: -1...1, locale: english), -1)
        editor.replaceText("0")
        XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, locale: english), 0.05)
        editor.replaceText("20")
        XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, locale: english), 1)
    }

    func testInvalidCommitPreservesCurrentValueAndRestoresText() {
        var editor = NumericEditingBuffer(value: 0.8, locale: english)
        for invalid in ["", "-", ".", "NaN", "inf", "0.45junk", "1.2.3", "1,000", "++1"] {
            editor.replaceText(invalid)
            XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, locale: english), 0.8)
            XCTAssertEqual(editor.text, "0.80")
        }
    }

    func testLocaleDecimalAndExternalValueSynchronization() {
        let german = Locale(identifier: "de_DE")
        var editor = NumericEditingBuffer(value: 0.8, locale: german)
        XCTAssertEqual(editor.text, "0,80")
        editor.replaceText("0,45")
        XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, locale: german), 0.45, accuracy: 0.000001)
        XCTAssertEqual(editor.text, "0,45")
        editor.synchronize(value: 0.25, locale: german)
        XCTAssertEqual(editor.text, "0,25")
    }

    func testFocusAndRepeatedCommitDoNotRoundUneditedValue() {
        let original: Float = 0.456789
        var editor = NumericEditingBuffer(value: original, locale: english)
        XCTAssertEqual(editor.text, "0.46")
        XCTAssertEqual(editor.commit(currentValue: original, range: 0.05...1, locale: english), original)
        editor.replaceText("0.455")
        let committed = editor.commit(currentValue: original, range: 0.05...1, locale: english)
        XCTAssertEqual(committed, 0.455)
        XCTAssertEqual(editor.commit(currentValue: committed, range: 0.05...1, locale: english), committed)
    }

    func testPercentageDisplayAndCommitUseHumanScale() {
        var editor = NumericEditingBuffer(value: 0.8, percent: true, locale: english)
        XCTAssertEqual(editor.text, "80")
        for input in ["45", "45%", "45 %"] {
            editor.replaceText(input)
            XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, percent: true, locale: english), 0.45, accuracy: 0.000001)
            XCTAssertEqual(editor.text, "45")
        }
        editor.replaceText("-45%")
        XCTAssertEqual(editor.commit(currentValue: 0, range: -1...1, percent: true, locale: english), -0.45, accuracy: 0.000001)
        editor.replaceText("0")
        XCTAssertEqual(editor.commit(currentValue: 0.8, range: 0.05...1, percent: true, locale: english), 0.05)
        XCTAssertEqual(editor.text, "5")
    }

    func testPercentageCommitIsLocalizedAndRejectsInvalidSuffixes() {
        let german = Locale(identifier: "de_DE")
        var editor = NumericEditingBuffer(value: 0.255, percent: true, locale: german)
        XCTAssertEqual(editor.text, "25,5")
        editor.replaceText("45,5%")
        XCTAssertEqual(editor.commit(currentValue: 0.255, range: 0.05...1, percent: true, locale: german), 0.455, accuracy: 0.000001)
        editor.replaceText("45%%")
        XCTAssertEqual(editor.commit(currentValue: 0.455, range: 0.05...1, percent: true, locale: german), 0.455)
        XCTAssertNil(InspectorNumberFormat.parse("45%", locale: english))
    }
}
