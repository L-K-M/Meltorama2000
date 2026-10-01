import Foundation

/// An Android project folder is also a Mac document package: project.json plus
/// untouched imported images. Keeping the bytes preserves EXIF and image quality.
public struct ProjectPackage: Sendable {
    public var document: ProjectDocument
    public var sourceData: Data
    public var fusionData: Data?

    public init(document: ProjectDocument = ProjectDocument(), sourceData: Data, fusionData: Data? = nil) {
        self.document = document; self.sourceData = sourceData; self.fusionData = fusionData
    }

    public static func read(url: URL) throws -> Self {
        let folder = url.lastPathComponent == "project.json" ? url.deletingLastPathComponent() : url
        let directory = try folder.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
        guard directory.isDirectory == true, directory.isSymbolicLink != true else { throw ProjectError.invalidPackage }
        let json = try assetData(name: "project.json", in: folder)
        let document = try ProjectDocument.decode(json)
        let source = try assetData(name: document.source, in: folder)
        let fusion = try document.fusion.map { try assetData(name: $0, in: folder) }
        guard !source.isEmpty, fusion.map({ !$0.isEmpty }) ?? true else { throw ProjectError.invalidPackage }
        return Self(document: document,sourceData: source,fusionData: fusion)
    }

    private static func assetData(name: String, in folder: URL) throws -> Data {
        let child = folder.appendingPathComponent(name, isDirectory: false)
        let values: URLResourceValues
        do { values = try child.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey]) }
        catch { throw ProjectError.missingAsset(name) }
        // Local names alone do not prevent a symbolic link from reading an
        // unrelated file. Imported packages may contain no such indirection.
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ProjectError.invalidAssetName }
        return try Data(contentsOf: child)
    }

    public func fileWrapper() throws -> FileWrapper {
        try document.validate()
        guard !sourceData.isEmpty, (document.fusion == nil) == (fusionData == nil) else { throw ProjectError.invalidPackage }
        var files = ["project.json": FileWrapper(regularFileWithContents: try document.encoded()),
                     document.source: FileWrapper(regularFileWithContents: sourceData)]
        if let name = document.fusion, let bytes = fusionData {
            guard !bytes.isEmpty else { throw ProjectError.invalidPackage }
            files[name] = FileWrapper(regularFileWithContents: bytes)
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }

    public init(fileWrapper: FileWrapper) throws {
        guard let children = fileWrapper.fileWrappers, let json = children["project.json"]?.regularFileContents else { throw ProjectError.invalidPackage }
        let document = try ProjectDocument.decode(json)
        guard let source = children[document.source]?.regularFileContents, !source.isEmpty else { throw ProjectError.missingAsset(document.source) }
        let fusion: Data?
        if let name = document.fusion {
            guard let bytes = children[name]?.regularFileContents, !bytes.isEmpty else { throw ProjectError.missingAsset(name) }
            fusion = bytes
        } else { fusion = nil }
        self.init(document: document,sourceData: source,fusionData: fusion)
    }

    /// NSDocument uses fileWrapper for its coordinated, autosaving write path.
    /// This convenience method is also atomic for CLI/testing and recovery.
    public func write(to url: URL) throws {
        let wrapper = try fileWrapper()
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
    }
}
