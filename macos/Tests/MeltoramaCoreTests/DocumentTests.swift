import Foundation
import XCTest
@testable import MeltoramaCore

final class DocumentTests: XCTestCase {
    private func stroke(_ n: Int, tool: BrushTool = .smear, target: Int64? = nil) -> Stroke {
        Stroke(tool:tool,radius:0.1,strength:0.7,stamps:[Stamp(cx:Float(n)/10,cy:0.5,dx:0.01,dy:-0.02)],targetRevision:target)
    }

    func testFixtureWrittenByAndroidSerializer() throws {
        // Generated through the existing Kotlin ProjectDocument serializer,
        // with defaults omitted, including all brush tools and new payloads.
        let url = try XCTUnwrap(Bundle.module.url(forResource:"android-project",withExtension:"json",subdirectory:"Fixtures"))
        let project = try ProjectDocument.decode(Data(contentsOf:url))
        XCTAssertEqual(try project.log.materialize().count,21)
        XCTAssertEqual(project.keyframes.count,2)
        XCTAssertEqual(project.globals.lenses.count,4)
        XCTAssertEqual(project.wobble.levers.count,6)
        XCTAssertEqual(project.wobble.levers[0],LeverWobble(rate:2,depth:0.2))
        XCTAssertEqual(try project.log.materialize().last?.pinWarp?.reach,1.5)
        XCTAssertEqual(project,try ProjectDocument.decode(project.encoded()))
    }

    func testOriginalAndroidSchemaWithOmittedDefaults() throws {
        // Shape produced by kotlinx.serialization with encodeDefaults=false.
        let json = #"{"schema":1,"globals":{"twirl":0.4},"log":{"revisions":[{"id":0},{"id":1,"parent":0,"stroke":{"tool":"SMEAR","radius":0.1,"strength":0.8,"stamps":[{"cx":0.5,"cy":0.4,"dx":0.01,"dy":0.0}]}}],"history":[0,1],"cursor":1},"keyframes":[{"revision":0},{"revision":1,"globals":{"bulge":0.5}}]}"#
        let project = try ProjectDocument.decode(Data(json.utf8))
        XCTAssertEqual(project.source,"source.img")
        XCTAssertEqual(project.globals.twirl,0.4)
        XCTAssertEqual(project.keyframes[0].easing,.linear)
        XCTAssertEqual(project.wobble,GlobalWobble())
        XCTAssertEqual(try project.log.materialize().count,1)
        XCTAssertEqual(project,try ProjectDocument.decode(project.encoded()))
    }

    func testWholeDocumentRoundTripIncludesAllBrushesAndPinWarp() throws {
        var log = StrokeLog()
        for tool in BrushTool.allCases where tool != .pins {
            try log.push(stroke(3,tool:tool,target:tool.needsTarget ? 0 : nil))
        }
        let warp = PinWarp(controls:[MlsControl(su:0.5,sv:0.5,tu:0.6,tv:0.4)])
        try log.push(Stroke(tool:.pins,radius:0.1,strength:1,pinWarp:warp))
        let globals = GlobalParams(bulge:0.2,twirl:-0.3,squeeze:0.1,stretch:-0.2,spike:0.4,static:0.7,lenses:LensType.allCases.map { Lens(u:0.4,v:0.6,type:$0) })
        let project = ProjectDocument(updatedAtMillis:1_700_000_000_000,fusion:"fusion.img",crop:CropRect(left:0.1,top:0.2,right:0.8,bottom:0.9),globals:globals,wobble:GlobalWobble(levers:[LeverWobble(rate:2,depth:0.3)]+Array(repeating:LeverWobble(),count:5)),log:log.snapshot(),keyframes:[KeyframeRecord(revision:0),KeyframeRecord(revision:log.currentRevision,globals:globals,easing:.boing)])
        XCTAssertEqual(project,try ProjectDocument.decode(project.encoded()))
    }

    func testUndoBranchesAndRewindTargetsRemainIndependent() throws {
        var log = StrokeLog()
        try log.push(stroke(1)); try log.push(stroke(2))
        let pin = log.currentRevision
        log.undo(); try log.push(stroke(3,tool:.rewind,target:pin))
        // No movie pin now retains target. The Rewind stroke itself must.
        let snapshot = log.snapshot()
        XCTAssertFalse(snapshot.history.contains(pin))
        XCTAssertEqual(try snapshot.materialize(revision:pin),[stroke(1),stroke(2)])
        var restored = try StrokeLog(snapshot:snapshot)
        restored.reset()
        XCTAssertEqual(restored.strokes,[])
        restored.undo()
        XCTAssertEqual(restored.strokes.last?.targetRevision,pin)
        restored.undo()
        XCTAssertEqual(restored.strokes,[stroke(1)])
        restored.redo()
        XCTAssertEqual(restored.strokes.count,2)
    }

    func testDeletedRedoBranchPinnedByKeyframeSurvivesSave() throws {
        var log = StrokeLog()
        try log.push(stroke(1)); try log.push(stroke(2))
        let pin = log.currentRevision
        log.undo(); try log.push(stroke(3))
        let project = ProjectDocument(log:log.snapshot(pins:[pin]),keyframes:[KeyframeRecord(revision:pin)])
        let restored = try ProjectDocument.decode(project.encoded())
        XCTAssertEqual(try restored.log.materialize(revision:pin),[stroke(1),stroke(2)])
        XCTAssertEqual(try restored.log.materialize(),[stroke(1),stroke(3)])
    }

    func testBatchIsOneUndoAndFailedBatchDoesNotChangeDocument() throws {
        var log = StrokeLog()
        try log.pushBatch([stroke(1),stroke(2),stroke(3)])
        XCTAssertEqual(log.strokes.count,3)
        log.undo(); XCTAssertEqual(log.strokes,[])
        log.redo(); XCTAssertEqual(log.strokes.count,3)
        let before = log.snapshot()
        XCTAssertThrowsError(try log.pushBatch([stroke(4),stroke(5,tool:.rewind,target:999)]))
        XCTAssertEqual(log.snapshot(),before)
    }

    func testMalformedDAGsAndUnusablePayloadsAreRefused() throws {
        var log = StrokeLog(); try log.push(stroke(1))
        let good = log.snapshot()
        var cases: [StrokeLogSnapshot] = []
        var bad = good; bad.history=[]; cases.append(bad)
        bad=good; bad.cursor=100; cases.append(bad)
        bad=good; bad.revisions.append(bad.revisions.last!); cases.append(bad)
        bad=good; bad.revisions[1].parent=1; cases.append(bad)
        bad=good; bad.revisions[0].parent=1; cases.append(bad)
        bad=good; bad.history.append(99); cases.append(bad)
        bad=good; bad.revisions[1].stroke?.stamps=[]; cases.append(bad)
        bad=good; bad.revisions[1].stroke?.radius=0; cases.append(bad)
        bad=good; bad.revisions[1].stroke=stroke(1,tool:.rewind,target:5); cases.append(bad)
        bad=good; bad.revisions[1].stroke?.stamps[0].cx = .nan; cases.append(bad)
        bad=good; bad.revisions[1].stroke?.pinWarp=PinWarp(controls:[MlsControl(su:0.4,sv:0.4,tu:0.6,tv:0.6)]); cases.append(bad)
        for snapshot in cases { XCTAssertThrowsError(try snapshot.validate()) }
        XCTAssertEqual(log.snapshot(),good)
    }

    func testUnknownEnumsRefusedAndUnknownOptionalFieldsIgnored() throws {
        let futureField = #"{"globals":{"bulge":0.5},"aFutureSetting":true}"#
        XCTAssertEqual(try ProjectDocument.decode(Data(futureField.utf8)).globals.bulge,0.5)
        let unknownTool = #"{"log":{"revisions":[{"id":0},{"id":1,"parent":0,"stroke":{"tool":"FUTURE_BRUSH","radius":0.1,"strength":1,"stamps":[{"cx":0.5,"cy":0.5,"dx":0,"dy":0}]}}],"history":[1]}}"#
        XCTAssertThrowsError(try ProjectDocument.decode(Data(unknownTool.utf8)))
        XCTAssertThrowsError(try ProjectDocument.decode(Data(#"{"globals":{"lenses":[{"u":0.5,"v":0.5,"type":"FUTURE_LENS"}]}}"#.utf8)))
    }

    func testUntrustedPathsAndBrokenPinsRefused() throws {
        for name in ["",".","..","../photo.jpg","sub/photo.jpg",#"sub\photo.jpg"#,"project.json","Project.JSON"] {
            XCTAssertThrowsError(try ProjectDocument(source:name).validate())
        }
        XCTAssertThrowsError(try ProjectDocument(keyframes:[KeyframeRecord(revision:999)]).validate())
        XCTAssertThrowsError(try ProjectDocument(crop:CropRect(left:0.8,top:0,right:0.3,bottom:1)).validate())
        XCTAssertThrowsError(try ProjectDocument(schema:99).validate())
        XCTAssertThrowsError(try ProjectDocument(source:"Source.img",fusion:"source.img").validate())
        XCTAssertThrowsError(try ProjectDocument(source:"é.img",fusion:"e\u{301}.img").validate())
    }

    func testPackageKeepsOriginalBytesAndReplacesAtomically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("Test.meltorama",isDirectory:true)
        let original = Data([0xFF,0xD8,1,2,3,4,0xFF,0xD9])
        let fusion = Data([0x89,0x50,0x4E,0x47,9,8,7])
        var package = ProjectPackage(document:ProjectDocument(fusion:"fusion.img"),sourceData:original,fusionData:fusion)
        try package.write(to:url)
        package.document.globals.twirl=0.4
        try package.write(to:url)
        let reopened = try ProjectPackage.read(url:url)
        XCTAssertEqual(reopened.document,package.document)
        XCTAssertEqual(reopened.sourceData,original)
        XCTAssertEqual(reopened.fusionData,fusion)
        let wrapperCopy = try ProjectPackage(fileWrapper:package.fileWrapper())
        XCTAssertEqual(wrapperCopy.sourceData,original)
        XCTAssertEqual(wrapperCopy.document,package.document)
    }

    func testPackageRejectsSymbolicLinkedAsset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try ProjectDocument().encoded().write(to:root.appendingPathComponent("project.json"))
        let outside = root.appendingPathComponent("original.img")
        try Data([1,2,3]).write(to:outside)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("source.img"),withDestinationURL:outside)
        XCTAssertThrowsError(try ProjectPackage.read(url:root))
    }
}
