import AppKit
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class SessionTests: XCTestCase {
    private func fixture() throws -> Data {
        let width = 64, height = 48
        let data = Data((0..<(width * height)).flatMap { point -> [UInt8] in
            [UInt8(point % width * 4), UInt8(point / width * 4), 127, 255]
        })
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let output = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return output as Data
    }

    @MainActor private func document() throws -> GooDocument {
        _ = NSApplication.shared
        let document = GooDocument()
        document.undoManager = UndoManager()
        document.undoManager?.groupsByEvent = false
        document.session.source = try fixture()
        document.session.imageSize = CGSize(width: 64, height: 48)
        return document
    }

    @MainActor private func action(_ document: GooDocument, _ body: () throws -> Void) rethrows {
        document.undoManager?.beginUndoGrouping()
        defer { document.undoManager?.endUndoGrouping() }
        try body()
    }

    private func stroke(_ value: Float) -> Stroke {
        Stroke(tool: .smear, radius: 0.15, strength: 0.8,
               stamps: [Stamp(cx: value, cy: 0.4, dx: 0.02, dy: 0.01)])
    }

    @MainActor func testUndoBranchRetainsLaterPinAndNeverReusesItsID() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        var log = StrokeLog()
        let first = stroke(0.3), second = stroke(0.5), replacement = stroke(0.7)
        try log.push(first)
        session.state.log = log.snapshot()
        action(document) {
            session.edit("Smear") { state in
                var log = try! StrokeLog(snapshot: state.log)
                try! log.push(second)
                state.log = log.snapshot()
            }
        }
        let pinnedRevision = session.currentRevision
        session.state.keyframes = [KeyframeRecord(revision: pinnedRevision)]
        document.undoManager?.undo()
        XCTAssertEqual(try session.state.log.materialize(), [first])
        XCTAssertEqual(session.state.keyframes.first?.revision, pinnedRevision)
        XCTAssertEqual(try session.state.log.materialize(revision: pinnedRevision), [first, second])

        action(document) {
            session.edit("Smear") { state in
                var log = try! StrokeLog(snapshot: state.log)
                try! log.push(replacement)
                state.log = log.snapshot(pins: state.keyframes.map(\.revision))
            }
        }
        XCTAssertGreaterThan(session.currentRevision, pinnedRevision)
        XCTAssertEqual(try session.state.log.materialize(), [first, replacement])
        XCTAssertEqual(try session.state.log.materialize(revision: pinnedRevision), [first, second])
        XCTAssertNoThrow(try session.state.validate())
    }

    @MainActor func testUndoCropRestoresPinsAndCoordinatesWithFreshRevisionIDs() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        var log = StrokeLog()
        try log.push(stroke(0.3)); try log.push(stroke(0.6))
        let original = ProjectDocument(globals: GlobalParams(twirl: 0.4), log: log.snapshot(pins: [1, 2]),
                                       keyframes: [KeyframeRecord(revision: 1), KeyframeRecord(revision: 2)])
        session.state = original
        let cropped = try EditorSession.cropping(original, to: CropRect(left: 0.1, top: 0.1, right: 0.8, bottom: 0.9))
        XCTAssertGreaterThan(cropped.log.currentRevision, original.log.revisions.map(\.id).max()!)
        action(document) { session.edit("Crop Photo") { $0 = cropped } }
        XCTAssertTrue(session.state.keyframes.isEmpty)
        document.undoManager?.undo()
        XCTAssertEqual(session.state.keyframes, original.keyframes)
        XCTAssertEqual(session.state.crop, original.crop)
        XCTAssertEqual(session.state.globals, original.globals)
        XCTAssertEqual(try session.state.log.materialize(), try original.log.materialize())
        XCTAssertNoThrow(try session.state.validate())
        document.undoManager?.redo()
        XCTAssertTrue(session.state.keyframes.isEmpty)
        XCTAssertEqual(session.state.crop, cropped.crop)
        XCTAssertEqual(session.currentRevision, cropped.log.currentRevision)
    }

    @MainActor func testExhaustedImportedRevisionsPreserveDocumentAcrossFailedEditsAndSave() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let lastID = Int64.max - 1
        let log = StrokeLogSnapshot(revisions: [StrokeRevisionRecord(id: 0),
            StrokeRevisionRecord(id: lastID, parent: 0, stroke: stroke(0.3))],
            history: [0, lastID], cursor: 1)
        let original = ProjectDocument(globals: GlobalParams(twirl: 0.4), log: log,
            keyframes: [KeyframeRecord(revision: lastID)])
        let package = ProjectPackage(document: original, sourceData: session.source)
        try document.read(from: package.fileWrapper(), ofType: "ch.lkmc.goo.project")
        document.updateChangeCount(.changeCleared)
        session.resetGoo()
        XCTAssertNotNil(session.error)
        XCTAssertEqual(session.state, original)
        session.error = nil
        session.dealGoo()
        XCTAssertNotNil(session.error)
        XCTAssertEqual(session.state, original)
        XCTAssertThrowsError(try EditorSession.cropping(original,
            to: CropRect(left: 0.1, top: 0.1, right: 0.8, bottom: 0.9)))
        session.activeStroke = stroke(0.6)
        session.finishStroke()
        XCTAssertNotNil(session.error)
        XCTAssertEqual(session.state, original)
        XCTAssertFalse(document.undoManager?.canUndo == true)
        XCTAssertFalse(document.isDocumentEdited)
        let saved = try ProjectPackage(fileWrapper: document.fileWrapper(ofType: "ch.lkmc.goo.project"))
        XCTAssertEqual(saved.document.log, original.log)
        XCTAssertEqual(saved.document.keyframes, original.keyframes)
        XCTAssertEqual(saved.document.globals, original.globals)
        XCTAssertEqual(saved.sourceData, package.sourceData)
    }

    @MainActor func testExhaustedActiveRevisionDoesNotReplaceLastRecoveryCheckpoint() async throws {
        let document = try document(), session = document.session
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("revision-recovery-\(UUID().uuidString)")
        defer { session.stopTimers(); try? FileManager.default.removeItem(at: root) }
        session.recoveryURL = root.appendingPathComponent("Draft.meltorama")
        let lastID = Int64.max - 1
        session.state.log = StrokeLogSnapshot(revisions: [StrokeRevisionRecord(id: 0),
            StrokeRevisionRecord(id: lastID, parent: 0, stroke: stroke(0.3))],
            history: [0, lastID], cursor: 1)
        session.writeRecovery()
        let before = try ProjectPackage.read(url: session.recoveryURL)
        session.activeStroke = stroke(0.6)
        session.writeRecovery()
        XCTAssertNotNil(session.error)
        let after = try ProjectPackage.read(url: session.recoveryURL)
        XCTAssertEqual(after.document, before.document)
        XCTAssertEqual(after.sourceData, before.sourceData)
    }

    @MainActor func testCaptureCommitsGestureBeforePinningAndCanBeUndone() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        action(document) {
            session.beginStroke(CGPoint(x: 0.3, y: 0.4), displayHeight: 600)
            session.extendStroke(CGPoint(x: 0.5, y: 0.4), displayHeight: 600)
            session.captureKeyframe()
        }
        let pin = try XCTUnwrap(session.state.keyframes.first)
        XCTAssertGreaterThan(pin.revision, 0)
        XCTAssertEqual(pin.revision, session.currentRevision)
        XCTAssertFalse(try session.state.log.materialize(revision: pin.revision).isEmpty)
        XCTAssertNil(session.activeStroke)
        document.undoManager?.undo()
        XCTAssertTrue(session.state.keyframes.isEmpty)
    }

    @MainActor func testUpdateFrameCommitsGestureBeforeRepinning() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        session.state.keyframes = [KeyframeRecord(revision: 0)]
        session.selectedKeyframe = 0
        action(document) {
            session.beginStroke(CGPoint(x: 0.3, y: 0.4), displayHeight: 600)
            session.extendStroke(CGPoint(x: 0.5, y: 0.4), displayHeight: 600)
            session.updateKeyframe()
        }
        XCTAssertGreaterThan(session.currentRevision, 0)
        XCTAssertEqual(session.state.keyframes[0].revision, session.currentRevision)
        XCTAssertNil(session.activeStroke)
    }

    @MainActor func testMeltUsesOriginalNoiseAndPortalsExpandInsideSymmetry() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        session.tool = .melt
        session.mirrored = true
        session.sectors = 3
        session.portalsEnabled = true
        session.portalPoints = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.7, y: 0.6)]
        action(document) {
            session.beginStroke(CGPoint(x: 0.2, y: 0.3), displayHeight: 600)
            let stamp = PumpStamps.at(tool: .melt, u: 0.2, v: 0.3, tick: 1)
            let pair = PortalPair(au: 0.2, av: 0.3, bu: 0.7, bv: 0.6)
            let shift = Portals.shiftAt(u: 0.2, v: 0.3, radius: session.radius, aspect: session.aspect, pair: pair)
            let expected = Portals.expand(stamp: stamp, shift: shift).flatMap {
                Symmetry.family(tool: .melt, stamp: $0, aspect: session.aspect, sectors: 3, mirrored: true)
            }
            XCTAssertEqual(session.activeStroke?.stamps, expected)
            XCTAssertEqual(expected.count, 12)
            session.finishStroke()
        }
        XCTAssertEqual(try session.state.log.materialize().first?.tool, .melt)
    }

    @MainActor func testDragUsesCoreResamplerAndPinsCarryReachAndRubber() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let start = CGPoint(x: 0.2, y: 0.4), end = CGPoint(x: 0.45, y: 0.5)
        let resampler = StrokeResampler(radius: session.radius, aspect: session.aspect,
            firstTravel: StrokeResampler.firstTravelFor(imageHeight: 600),
            maxSpacing: StrokeResampler.maxSpacingFor(imageHeight: 600))
        resampler.begin(u: Float(start.x), v: Float(start.y))
        let expected = resampler.extend(u: Float(end.x), v: Float(end.y))
        action(document) {
            session.beginStroke(start, displayHeight: 600)
            session.extendStroke(end, displayHeight: 600)
            XCTAssertEqual(session.activeStroke?.stamps, expected)
            session.finishStroke()
        }
        session.tool = .pins
        session.pinReach = 2.3; session.pinRubber = 0.65
        session.holds = [CGPoint(x: 0.3, y: 0.3)]
        action(document) {
            session.beginStroke(CGPoint(x: 0.5, y: 0.5))
            session.extendStroke(CGPoint(x: 0.65, y: 0.6))
            XCTAssertEqual(session.activeStroke?.pinWarp?.reach, 2.3)
            XCTAssertEqual(session.activeStroke?.pinWarp?.rubber, 0.65)
            XCTAssertEqual(session.activeStroke?.pinWarp?.controls.count, 6)
            session.finishStroke()
        }
        XCTAssertNoThrow(try session.state.validate())
    }

    @MainActor func testPreviewBoingAndWobbleUseTheExportMath() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        session.state.keyframes = [KeyframeRecord(revision: 0, easing: .boing),
                                  KeyframeRecord(revision: 0, globals: GlobalParams(twirl: 0.9))]
        session.live = false; session.playing = true; session.scrub = 0.58
        let tween = try XCTUnwrap(session.previewTween())
        XCTAssertGreaterThan(tween.fraction, 1)
        XCTAssertEqual(tween.globals.twirl, 0.9)
        session.state.wobble.levers[0] = LeverWobble(rate: 8, depth: 0.3)
        let rig = session.state.wobble.cappedFor(loopSeconds: MovieSpec(keyframeCount: 2).durationSeconds)
        let globals = session.state.keyframes[0].globals.lerp(session.state.keyframes[1].globals,
            t: leverProgress(0.58, easing: .boing))
        let expected = leversAt(base: globals, wobble: rig, phase: 0.58)
        XCTAssertEqual(session.previewTween()?.globals, expected)
    }

    @MainActor func testUndoBackToSavedDocumentClearsDirtyState() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        document.updateChangeCount(.changeCleared)
        action(document) { session.edit("Adjust Twirl") { $0.globals.twirl = 0.4 } }
        XCTAssertTrue(document.isDocumentEdited)
        document.undoManager?.undo()
        XCTAssertEqual(session.state.globals.twirl, 0)
        XCTAssertFalse(document.isDocumentEdited)
        document.undoManager?.redo()
        XCTAssertTrue(document.isDocumentEdited)
    }

    @MainActor func testFirstRecoveryCreatesItsFolderAndRoundTripsDocument() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        session.recoveryURL = root.appendingPathComponent("Recovery/Draft.meltorama")
        session.state.globals.twirl = 0.3
        session.writeRecovery()
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.recoveryURL.path))
        let recovered = try ProjectPackage.read(url: session.recoveryURL)
        XCTAssertEqual(recovered.document, session.state)
        XCTAssertEqual(recovered.sourceData, session.source)
    }

    @MainActor func testCheckpointIncludesActiveGestureWithoutCommittingLiveHistory() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        session.recoveryURL = root.appendingPathComponent("Recovery/Draft.meltorama")
        action(document) {
            session.beginStroke(CGPoint(x: 0.25, y: 0.4), displayHeight: 600)
            session.extendStroke(CGPoint(x: 0.55, y: 0.45), displayHeight: 600)
            let liveLog = session.state.log
            let active = session.activeStroke
            session.writeRecovery()
            XCTAssertEqual(session.state.log, liveLog)
            do {
                let recovered = try ProjectPackage.read(url: session.recoveryURL)
                XCTAssertEqual(try recovered.document.log.materialize(), active.map { [$0] } ?? [])
                XCTAssertGreaterThan(recovered.document.log.currentRevision, session.currentRevision)
                XCTAssertNoThrow(try recovered.document.validate())
            } catch { XCTFail(error.localizedDescription) }
            session.finishStroke()
        }
    }

    @MainActor func testDocumentWindowRoutesUndoAndRedoKeyEquivalents() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        func findCanvas(_ view: NSView) -> PhotoCanvas? {
            if let canvas = view as? PhotoCanvas { return canvas }
            return view.subviews.compactMap(findCanvas).first
        }
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findCanvas(content))
        XCTAssertTrue(window.makeFirstResponder(canvas))
        action(document) { session.edit("Adjust Twirl") { $0.globals.twirl = 0.4 } }
        let undo = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        XCTAssertTrue(window.performKeyEquivalent(with: undo))
        XCTAssertEqual(session.state.globals.twirl, 0)
        let redo = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "Z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        XCTAssertTrue(window.performKeyEquivalent(with: redo))
        XCTAssertEqual(session.state.globals.twirl, 0.4)
        window.orderOut(nil)
    }

    @MainActor func testNativeTextUndoKeyIsNotRoutedToDocumentHistory() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        let fieldEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = fieldEditor
        XCTAssertTrue(window.makeFirstResponder(fieldEditor))
        action(document) { session.edit("Adjust Twirl") { $0.globals.twirl = 0.4 } }
        let undo = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        _ = window.performKeyEquivalent(with: undo)
        XCTAssertEqual(session.state.globals.twirl, 0.4)
        XCTAssertTrue(document.undoManager?.canUndo == true)
        window.orderOut(nil)
    }

    @MainActor func testActiveExportCannotOpenAnotherSavePanelOrEnableContextCommand() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        XCTAssertTrue(session.canExport)
        session.progress = 0.37
        let previous = session.state
        XCTAssertFalse(session.canExport)
        session.export(options: ExportOptions(format: .png))
        XCTAssertEqual(session.progress, 0.37)
        XCTAssertEqual(session.state, previous)
        let canvas = PhotoCanvas(frame: .zero)
        canvas.session = session
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let command = try XCTUnwrap(canvas.menu(for: event)?.items.last)
        XCTAssertFalse(command.isEnabled)
    }

    @MainActor func testReadDiscardsOldGestureBeforeReplacingDocument() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let saved = ProjectDocument(globals: GlobalParams(twirl: 0.2), keyframes: [KeyframeRecord(revision: 0)])
        let package = ProjectPackage(document: saved, sourceData: session.source, fusionData: nil)
        session.tool = .grow
        session.beginStroke(CGPoint(x: 0.3, y: 0.4), displayHeight: 600)
        XCTAssertTrue(session.activeStroke?.hasContent == true)
        XCTAssertThrowsError(try document.read(from: FileWrapper(directoryWithFileWrappers: [:]), ofType: "ch.lkmc.goo.project"))
        XCTAssertTrue(session.activeStroke?.hasContent == true)
        try document.read(from: package.fileWrapper(), ofType: "ch.lkmc.goo.project")
        XCTAssertNil(session.activeStroke)
        session.finishStroke()
        XCTAssertEqual(session.state, saved)
        XCTAssertTrue(try session.state.log.materialize().isEmpty)
        XCTAssertFalse(document.undoManager?.canUndo == true)
    }

    @MainActor func testQueuedExportProgressCannotReviveCompletionOrChangeANewExport() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let firstID = try XCTUnwrap(session.beginExportTracking())
        DispatchQueue.main.async { session.applyExportProgress(0.95, exportID: firstID) }
        session.finishExportTracking(firstID)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertNil(session.progress)
        XCTAssertNil(session.activeExportID)
        XCTAssertTrue(session.canExport)

        let secondID = try XCTUnwrap(session.beginExportTracking())
        XCTAssertNotEqual(firstID, secondID)
        session.applyExportProgress(0.2, exportID: secondID)
        DispatchQueue.main.async { session.applyExportProgress(1, exportID: firstID) }
        session.finishExportTracking(firstID)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(session.progress, 0.2)
        XCTAssertEqual(session.activeExportID, secondID)
        session.cancelExport()
        XCTAssertEqual(session.activeExportID, secondID)
        XCTAssertFalse(session.canExport)
        session.finishExportTracking(secondID)
        XCTAssertNil(session.progress)
        XCTAssertNil(session.activeExportID)
    }

    @MainActor func testContinuousSliderAcrossEventsUndoesOnceAndRestoresSavedState() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let manager = try XCTUnwrap(document.undoManager)
        manager.groupsByEvent = true
        document.updateChangeCount(.changeCleared)
        session.beginContinuousEdit()
        session.beginContinuousEdit()
        for value: Float in [0.1, 0.2, 0.3] {
            session.edit("Adjust Twirl") { $0.globals.twirl = value }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        session.endContinuousEdit()
        session.endContinuousEdit()
        XCTAssertEqual(manager.groupingLevel, 0)
        XCTAssertTrue(manager.groupsByEvent)
        XCTAssertTrue(document.isDocumentEdited)
        manager.undo()
        XCTAssertEqual(session.state.globals.twirl, 0)
        XCTAssertFalse(document.isDocumentEdited)
        manager.redo()
        XCTAssertEqual(session.state.globals.twirl, 0.3)
        XCTAssertTrue(document.isDocumentEdited)
    }

    @MainActor func testContinuousSliderSeparatesPriorEventAndBalancesAtDocumentBoundaries() async throws {
        let document = try document(), session = document.session
        defer { session.stopTimers() }
        let manager = try XCTUnwrap(document.undoManager)
        manager.groupsByEvent = true
        session.edit("Adjust Bulge") { $0.globals.bulge = 0.2 }
        session.beginContinuousEdit()
        session.edit("Adjust Twirl") { $0.globals.twirl = 0.2 }
        session.edit("Adjust Twirl") { $0.globals.twirl = 0.4 }
        session.finishStroke()
        XCTAssertEqual(manager.groupingLevel, 0)
        XCTAssertTrue(manager.groupsByEvent)
        manager.undo()
        XCTAssertEqual(session.state.globals.twirl, 0)
        XCTAssertEqual(session.state.globals.bulge, 0.2)
        manager.undo()
        XCTAssertEqual(session.state.globals.bulge, 0)

        session.beginContinuousEdit()
        session.edit("Adjust Twirl") { $0.globals.twirl = 0.6 }
        let package = ProjectPackage(document: ProjectDocument(), sourceData: session.source, fusionData: nil)
        session.replacePackage(package, name: "Saved", markEdited: false)
        XCTAssertEqual(manager.groupingLevel, 0)
        XCTAssertTrue(manager.groupsByEvent)
        XCTAssertFalse(manager.canUndo)
        session.beginContinuousEdit()
        session.edit("Adjust Twirl") { $0.globals.twirl = 0.2 }
        session.stopTimers()
        XCTAssertEqual(manager.groupingLevel, 0)
        XCTAssertTrue(manager.groupsByEvent)
    }
}
