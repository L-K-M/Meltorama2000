import Foundation
import MeltoramaCore

/// SwiftPM resources are a separate bundle inside the installed application.
/// Both native AppKit copy and SwiftUI labels resolve against that same bundle.
enum ResourceBundleResolver {
    static let name = "Meltorama_MeltoramaMac.bundle"

    static func contains(_ resource: URL, in application: URL) -> Bool {
        let root = application.resolvingSymlinksInPath().standardizedFileURL.path
        let child = resource.resolvingSymlinksInPath().standardizedFileURL.path
        return child.hasPrefix(root + "/")
    }

    static func resolve(in application: Bundle, developmentBundle: () -> Bundle) -> Bundle? {
        guard application.bundleURL.pathExtension.lowercased() == "app" else { return developmentBundle() }
        // Physical lookup avoids resource indexing differences between the flat
        // SwiftPM bundle and Xcode's Contents/Resources bundle. Foundation may
        // normalize /private/tmp to /tmp when constructing the nested Bundle.
        let roots = [application.resourceURL,
                     application.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)].compactMap { $0 }
        for root in roots {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            guard contains(candidate, in: application.bundleURL),
                  let bundle = Bundle(url: candidate),
                  contains(bundle.bundleURL, in: application.bundleURL) else { continue }
            return bundle
        }
        return nil
    }
}

let ResourceBundle: Bundle = {
    guard let bundle = ResourceBundleResolver.resolve(in: .main, developmentBundle: { .module }) else {
        fatalError("The installed Meltorama application is missing its resource bundle in Contents/Resources.")
    }
    return bundle
}()

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: ResourceBundle, comment: "")
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

/// Keep Foundation's system errors intact. Document validation stays in the
/// portable core; its user-facing description is localized at the Mac boundary.
func localizedError(_ error: Error) -> NSError {
    let original = error as NSError
    guard let project = error as? ProjectError else { return original }
    let description: String
    switch project {
    case .unsupportedSchema(let schema): description = LF("This project uses unsupported document version %d.", schema)
    case .invalidAssetName: description = L("The project contains an invalid image filename.")
    case .missingAsset(let name): description = LF("The project's image %@ is missing.", name)
    case .invalidHistory: description = L("The project's undo history is damaged.")
    case .invalidRevision(let id): description = LF("The project contains a damaged revision (%@).", String(id))
    case .invalidStroke(let id): description = LF("The project contains an invalid brush edit (revision %@).", String(id))
    case .invalidCrop: description = L("The project's crop is invalid.")
    case .invalidGlobals: description = L("The project contains invalid effect settings.")
    case .invalidKeyframe: description = L("An animation keyframe refers to a missing revision.")
    case .invalidPackage: description = L("Choose a Meltorama project package or an Android project folder.")
    }
    var info = original.userInfo
    info[NSLocalizedDescriptionKey] = description
    info[NSUnderlyingErrorKey] = error
    return NSError(domain: original.domain, code: original.code, userInfo: info)
}
