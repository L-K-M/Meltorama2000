import Foundation
import XCTest
@testable import MeltoramaMac

final class ResourceBundleTests: XCTestCase {
    private enum Layout { case flat, contents }

    private func fixture(at root: URL, layout: Layout?) throws -> Bundle {
        let app = root.appendingPathComponent("Meltorama.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        func plist(_ url: URL, type: String) throws {
            let values = ["CFBundleIdentifier": "test.resources.\(UUID().uuidString)", "CFBundlePackageType": type,
                          "CFBundleName": "Meltorama", "CFBundleDevelopmentRegion": "en"]
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: url)
        }
        try plist(contents.appendingPathComponent("Info.plist"), type: "APPL")
        if let layout {
            let bundle = contents.appendingPathComponent("Resources/\(ResourceBundleResolver.name)", isDirectory: true)
            let resources: URL
            switch layout {
            case .flat:
                resources = bundle
                try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                try plist(bundle.appendingPathComponent("Info.plist"), type: "BNDL")
            case .contents:
                resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
                try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                try plist(bundle.appendingPathComponent("Contents/Info.plist"), type: "BNDL")
            }
            try Data("resource fixture".utf8).write(to: resources.appendingPathComponent("marker.txt"))
            let chinese = resources.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: chinese, withIntermediateDirectories: true)
            try Data("\"Fixture\" = \"资源测试\";\n".utf8).write(to: chinese.appendingPathComponent("Localizable.strings"))
        }
        return try XCTUnwrap(Bundle(url: app))
    }

    func testRelocatedFlatAndXcodeResourceBundlesResolveInsideApplication() throws {
        for layout in [Layout.flat, .contents] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("resources-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = try fixture(at: root, layout: layout)
            var usedDevelopmentBundle = false
            let bundle = try XCTUnwrap(ResourceBundleResolver.resolve(in: app) { usedDevelopmentBundle = true; return ResourceBundle })
            XCTAssertFalse(usedDevelopmentBundle)
            XCTAssertTrue(ResourceBundleResolver.contains(bundle.bundleURL, in: app.bundleURL))
            let marker = try XCTUnwrap(bundle.url(forResource: "marker", withExtension: "txt"))
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "resource fixture")
            let chineseURL = try XCTUnwrap(bundle.url(forResource: "zh-Hans", withExtension: "lproj"))
            XCTAssertEqual(NSLocalizedString("Fixture", bundle: try XCTUnwrap(Bundle(url: chineseURL)), comment: ""), "资源测试")
        }
    }

    func testInstalledApplicationNeverFallsBackToDevelopmentResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("missing-resources-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(at: root, layout: nil)
        var usedDevelopmentBundle = false
        XCTAssertNil(ResourceBundleResolver.resolve(in: app) { usedDevelopmentBundle = true; return ResourceBundle })
        XCTAssertFalse(usedDevelopmentBundle)
    }

    func testContainmentResolvesPathAliasesAndRejectsExternalResources() throws {
        let root = URL(fileURLWithPath: "/private/tmp/resource-alias-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(at: root, layout: .contents)
        let privateApp = root.appendingPathComponent("Meltorama.app")
        let aliasedApp = URL(fileURLWithPath: privateApp.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"))
        let resource = aliasedApp.appendingPathComponent("Contents/Resources/\(ResourceBundleResolver.name)")
        XCTAssertFalse(resource.path.hasPrefix(privateApp.path + "/"))
        XCTAssertTrue(ResourceBundleResolver.contains(resource, in: privateApp))
        XCTAssertFalse(ResourceBundleResolver.contains(URL(fileURLWithPath: "/private/tmp/unrelated.bundle"), in: app.bundleURL))
    }
}
