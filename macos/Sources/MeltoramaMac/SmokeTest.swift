import AppKit
import ImageIO
import MeltoramaCore

enum SmokeTest {
    static func run() {
        do {
            let applicationURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
            let resourceURL = ResourceBundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL
            if applicationURL.pathExtension == "app",
               !resourceURL.path.hasPrefix(applicationURL.path + "/") {
                throw NSError(domain: "SmokeTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Installed application at \(Bundle.main.bundleURL.path) used resources at \(ResourceBundle.bundleURL.path)"])
            }
            let engine = try WarpEngine()
            guard let sample = ResourceBundle.url(forResource:"goo-guy",withExtension:"png") else {throw WarpError.invalidImage}
            let source=try Data(contentsOf:sample)
            let sourceSize=try WarpEngine.imageSize(data:source)
            let original=try WarpEngine.decodedImage(data:source,maxDimension:Int(max(sourceSize.width,sourceSize.height)))
            var project=ProjectDocument()
            let first=project.log.history[project.log.cursor]
            let identity=try engine.render(document:project,source:source,fusion:nil,size:CGSize(width:original.width,height:original.height))
            guard pixels(identity)==pixels(original) else {throw NSError(domain:"SmokeTest",code:1,userInfo:[NSLocalizedDescriptionKey:"Identity render differs from source"])}
            var log=try StrokeLog(snapshot:project.log)
            try log.push(Stroke(tool:.smear,radius:0.2,strength:1,stamps:[Stamp(cx:0.5,cy:0.5,dx:0.08,dy:0.03)]))
            project.log=log.snapshot()
            let end=project.log.history[project.log.cursor]
            project.keyframes=[KeyframeRecord(revision:first),KeyframeRecord(revision:end)]
            let edited=try engine.render(document:project,source:source,fusion:nil,size:CGSize(width:original.width,height:original.height))
            guard pixels(edited) != pixels(identity) else {throw NSError(domain:"SmokeTest",code:2,userInfo:[NSLocalizedDescriptionKey:"Brush did not change image"])}
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meltorama-smoke-\(UUID().uuidString).meltorama")
            defer {try? FileManager.default.removeItem(at:folder)}
            try ProjectPackage(document:project,sourceData:source,fusionData:nil).write(to:folder)
            let restored=try ProjectPackage.read(url:folder)
            let reopened=try engine.render(document:restored.document,source:restored.sourceData,fusion:nil,size:CGSize(width:original.width,height:original.height))
            guard pixels(reopened)==pixels(edited) else {throw NSError(domain:"SmokeTest",code:3,userInfo:[NSLocalizedDescriptionKey:"Save/reopen changed rendering"])}
            print("PASS: GPU identity, brush edit, project save/reopen, pinned revisions; texture limit \(engine.maxTextureSize)")
        } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    private static func pixels(_ image:CGImage)->Data {
        var data=Data(count:image.width*image.height*4)
        data.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return data
    }
}
