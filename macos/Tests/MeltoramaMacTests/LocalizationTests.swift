import Foundation
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class LocalizationTests: XCTestCase {
    private func table(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(ResourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    func testEnglishAndSimplifiedChineseHaveMatchingKeysAndFormatArguments() throws {
        let english = try table("en"), chinese = try table("zh-Hans")
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        XCTAssertGreaterThan(english.count, 250)
        let format = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|j|z|t|L)?[@diuoxXfFeEgGaAcCsSp%]"#)
        func arguments(_ text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return format.matches(in: text, range: range).compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                let token = String(text[range])
                return token == "%%" ? nil : token
            }
        }
        for (key, value) in english {
            let translated = try XCTUnwrap(chinese[key])
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(arguments(value), arguments(translated), key)
        }
    }

    func testToolLensEasingAndNativeCommandsResolveInChinese() throws {
        let chinese = try table("zh-Hans")
        for tool in BrushTool.allCases { XCTAssertNotNil(chinese[tool.title], tool.title) }
        for lens in LensType.allCases { XCTAssertNotNil(chinese["Lens \(lens.title)"], lens.title) }
        for easing in Easing.allCases { XCTAssertNotNil(chinese[easing.title], easing.title) }
        for preference in AppearancePreference.allCases { XCTAssertNotNil(chinese[preference.title], preference.title) }
        for preference in ThemePreference.allCases { XCTAssertNotNil(chinese[preference.title], preference.title) }
        for key in ["File", "Open…", "Save…", "Revert to Saved…", "Return to Full Photo", "Whole Photo Effects", "Export…", "Loop forever", "Enter Full Screen", "Exit Full Screen"] {
            XCTAssertNotEqual(chinese[key], key)
        }
        let url = try XCTUnwrap(ResourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "zh-Hans.lproj"))
        let bundle = try XCTUnwrap(Bundle(url: url.deletingLastPathComponent()))
        XCTAssertEqual(NSLocalizedString("File", bundle: bundle, comment: ""), "文件")
        XCTAssertEqual(String(format: NSLocalizedString("Frame %d", bundle: bundle, comment: ""), 3), "第 3 帧")
    }

    func testProjectErrorMappingPreservesValuesAndSystemErrors() throws {
        let name = "My 照片.img"
        let project = ProjectError.missingAsset(name)
        let mapped = localizedError(project)
        XCTAssertTrue(mapped.localizedDescription.contains(name))
        XCTAssertEqual(mapped.domain, (project as NSError).domain)
        XCTAssertEqual(mapped.code, (project as NSError).code)
        XCTAssertNotNil(mapped.userInfo[NSUnderlyingErrorKey] as? ProjectError)
        let revision = localizedError(ProjectError.invalidRevision(Int64.max))
        XCTAssertTrue(revision.localizedDescription.contains(String(Int64.max)))
        let exhausted = localizedError(ProjectError.revisionLimitReached)
        XCTAssertEqual(exhausted.localizedDescription,
            L("This project has reached its edit limit. Export the photo to start a new project."))
        XCTAssertNotNil(exhausted.userInfo[NSUnderlyingErrorKey] as? ProjectError)
        let external = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                               userInfo: [NSFilePathErrorKey: name])
        XCTAssertTrue(localizedError(external) === external)
    }

    @MainActor func testAppearanceIsAppliedOnlyToThisApplication() async {
        _ = NSApplication.shared
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        AppearancePreference.light.apply()
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        AppearancePreference.dark.apply()
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        AppearancePreference.system.apply()
        XCTAssertNil(NSApp.appearance)
    }
}
