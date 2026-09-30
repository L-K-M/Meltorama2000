import SwiftUI
import AppKit
import MeltoramaCore

struct CanvasView: NSViewRepresentable {
    @ObservedObject var session: EditorSession
    func makeNSView(context: Context) -> PhotoCanvas {
        let view = PhotoCanvas()
        view.session = session
        return view
    }
    func updateNSView(_ nsView: PhotoCanvas, context: Context) { nsView.session = session; nsView.updateViewport(); nsView.needsDisplay = true }
}

final class PhotoCanvas: NSView {
    weak var session: EditorSession?
    private var tracking: NSTrackingArea?
    private var pointer: CGPoint?
    private var spaceDown = false
    private var panStart: CGPoint?
    private var originalPan = CGPoint.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { session?.document?.undoManager ?? super.undoManager }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L("Photo editing canvas"))
        setAccessibilityHelp(L("Drag to use the selected tool. Hold Space to pan. Pinch to zoom. Bracket keys change brush size."))
    }
    required init?(coder: NSCoder) {fatalError("Not supported")}
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateViewport(); window?.makeFirstResponder(self) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateViewport() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateViewport() }
    func updateViewport() { session?.updateViewport(size: bounds.size, backingScale: window?.backingScaleFactor ?? 1) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    private var imageRect:CGRect {
        guard let session else {return .zero}
        return CanvasGeometry.imageRect(image: session.imageSize, viewport: bounds.size, zoom: session.zoom, pan: session.pan)
    }
    private func point(_ event:NSEvent)->CGPoint {convert(event.locationInWindow,from:nil)}
    private func imagePoint(_ p:CGPoint)->CGPoint {
        guard let session else {return .zero}
        return CanvasGeometry.sourcePoint(p, imageRect: imageRect, rotation: session.rotation)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.underPageBackgroundColor.setFill();bounds.fill()
        guard let session,let image=session.image else {
            if session?.rendering == true {let text=NSAttributedString(string:L("Preparing Photo…"),attributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.secondaryLabelColor]);text.draw(at:CGPoint(x:bounds.midX-65,y:bounds.midY))};return
        }
        let rect=imageRect
        NSGraphicsContext.saveGraphicsState()
        let transform=AffineTransform(translationByX:rect.midX,byY:rect.midY)
        var rotate=AffineTransform();rotate.rotate(byDegrees:session.rotation)
        var drawing=transform;drawing.append(rotate);drawing.translate(x:-rect.midX,y:-rect.midY)
        (drawing as NSAffineTransform).concat()
        let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.3);shadow.shadowBlurRadius=12;shadow.shadowOffset=NSSize(width:0,height:2);shadow.set()
        NSColor.textBackgroundColor.setFill();rect.fill()
        NSShadow().set()
        NSImage(cgImage:image,size:session.imageSize).draw(in:rect,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        func screen(_ p:CGPoint)->CGPoint {CGPoint(x:rect.minX+p.x*rect.width,y:rect.minY+p.y*rect.height)}
        func ring(_ point:CGPoint,_ radius:CGFloat,_ color:NSColor,_ title:String?=nil) {
            let center=screen(point)
            let path=NSBezierPath(ovalIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
            color.setStroke();path.lineWidth=1.5;path.stroke()
            if let title {NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:color,.backgroundColor:NSColor.textBackgroundColor.withAlphaComponent(0.8)]).draw(at:CGPoint(x:center.x+radius+4,y:center.y-8))}
        }
        if session.mode == .lenses {
            for (index,lens) in session.state.globals.lenses.enumerated() {ring(CGPoint(x:CGFloat(lens.u),y:CGFloat(lens.v)),CGFloat(lens.radius)*rect.height,index==session.selectedLens ? .controlAccentColor : .white,"\(index+1)");ring(CGPoint(x:CGFloat(lens.u),y:CGFloat(lens.v)),4,.controlAccentColor)}
        }
        if session.tool == .echo,let anchor=session.echoAnchor {ring(anchor,8,.systemOrange,L("Source"))}
        if session.portalsEnabled {for (index,point) in session.portalPoints.enumerated() {ring(point,CGFloat(session.radius)*rect.height,index==0 ? .systemOrange : .systemBlue,index==0 ? "A" : "B")}}
        if session.tool == .pins {for (index,point) in session.holds.enumerated() {ring(point,6,.systemOrange,"\(index+1)")}}
        if session.mode == .crop,let crop=session.cropRect {
            let area=CGRect(x:rect.minX+crop.minX*rect.width,y:rect.minY+crop.minY*rect.height,width:crop.width*rect.width,height:crop.height*rect.height)
            NSColor.controlAccentColor.setStroke();let path=NSBezierPath(rect:area);path.lineWidth=2;path.stroke()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            for step in 1...2 {let x=area.minX+area.width*CGFloat(step)/3,y=area.minY+area.height*CGFloat(step)/3;let line=NSBezierPath();line.move(to:CGPoint(x:x,y:area.minY));line.line(to:CGPoint(x:x,y:area.maxY));line.move(to:CGPoint(x:area.minX,y:y));line.line(to:CGPoint(x:area.maxX,y:y));line.lineWidth=0.5;line.stroke()}
        }
        NSGraphicsContext.restoreGraphicsState()
        if let p=pointer,session.mode == .brush,session.tool != .pins,!spaceDown,!UserDefaults.standard.bool(forKey:"hideBrushCursor") {
            let radius=CGFloat(session.radius)*rect.height
            let path=NSBezierPath(ovalIn:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2))
            NSColor.black.withAlphaComponent(0.65).setStroke();path.lineWidth=3;path.stroke()
            NSColor.white.withAlphaComponent(0.9).setStroke();path.lineWidth=1;path.stroke()
        }
    }
    override func mouseMoved(with event:NSEvent) {pointer=point(event);needsDisplay=true}
    override func mouseExited(with event:NSEvent) {pointer=nil;needsDisplay=true}
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        guard let session else {return}
        let p=point(event);pointer=p
        if spaceDown || session.mode == .hand {panStart=p;originalPan=session.pan;NSCursor.closedHand.push();return}
        let uv=imagePoint(p)
        guard (0...1).contains(uv.x),(0...1).contains(uv.y) else {return}
        session.beginStroke(uv,option:event.modifierFlags.contains(.option),displayHeight:imageRect.height)
    }
    override func mouseDragged(with event:NSEvent) {
        guard let session else {return}
        let p=point(event);pointer=p
        if let start=panStart {session.pan=CGPoint(x:originalPan.x+p.x-start.x,y:originalPan.y+p.y-start.y);needsDisplay=true;return}
        session.extendStroke(imagePoint(p),displayHeight:imageRect.height)
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {if panStart != nil {panStart=nil;NSCursor.pop()} else {session?.finishStroke()};needsDisplay=true}
    override func otherMouseDown(with event:NSEvent) {panStart=point(event);originalPan=session?.pan ?? .zero}
    override func otherMouseDragged(with event:NSEvent) {mouseDragged(with:event)}
    override func otherMouseUp(with event:NSEvent) {panStart=nil}
    override func magnify(with event:NSEvent) {session?.zoom=min(16,max(0.1,(session?.zoom ?? 1)*(1+event.magnification)));needsDisplay=true}
    override func rotate(with event:NSEvent) {session?.rotation -= CGFloat(event.rotation);needsDisplay=true}
    override func scrollWheel(with event:NSEvent) {
        guard let session else {return}
        if event.modifierFlags.contains(.option) {session.zoom=min(16,max(0.1,session.zoom*(1+event.scrollingDeltaY/100)))}
        else {session.pan.x -= event.scrollingDeltaX;session.pan.y -= event.scrollingDeltaY}
        needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        guard let session else {return}
        switch event.charactersIgnoringModifiers {
        case " ":if !spaceDown {spaceDown=true;NSCursor.openHand.push()}
        case "[":session.radius=max(0.01,session.radius/1.15)
        case "]":session.radius=min(0.28,session.radius*1.15)
        case "b":session.mode = .brush
        case "h":session.mode = .hand
        case "l":session.mode = .lenses
        case "c":session.mode = .crop
        case "\u{1b}":session.finishStroke();session.cropRect=nil;session.playing=false;session.live=true;session.requestRender()
        case "\u{7f}":
            if session.mode == .lenses,let index=session.selectedLens,session.state.globals.lenses.indices.contains(index) {session.edit("Remove Lens") {$0.globals.lenses.remove(at:index)};session.selectedLens=nil}
            else if session.showTimeline {session.deleteFrame()}
        default:super.keyDown(with:event)
        }
        needsDisplay=true
    }
    override func keyUp(with event:NSEvent) {if event.charactersIgnoringModifiers==" " && spaceDown {spaceDown=false;NSCursor.pop();needsDisplay=true} else {super.keyUp(with:event)}}
    override func resignFirstResponder()->Bool {if spaceDown {spaceDown=false;NSCursor.pop()};session?.finishStroke();return super.resignFirstResponder()}
    override func menu(for event:NSEvent)->NSMenu? {
        let menu=NSMenu()
        menu.autoenablesItems = false
        for (title,selector) in [("Fit in Window",#selector(fit)),("Compare Original",#selector(compare)),("Capture GOOvie Frame",#selector(capture)),("Export…",#selector(exportPhoto))] {let item=NSMenuItem(title:L(title),action:selector,keyEquivalent:"");item.target=self;item.isEnabled = selector == #selector(exportPhoto) ? (session?.canExport ?? false) : (session?.hasPhoto ?? false);menu.addItem(item)}
        return menu
    }
    @objc private func fit(){session?.resetView()}
    @objc private func compare(){session?.compareOriginal.toggle();session?.requestRender()}
    @objc private func capture(){session?.captureKeyframe()}
    @objc private func exportPhoto(){if session?.canExport == true {session?.showExport=true}}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {.copy}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let url=(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:nil) as? [URL])?.first else {return false}
        // An incoming photo opens a separate document, preserving the current work.
        (NSApp.delegate as? AppDelegate)?.application(NSApp,open:[url]);return true
    }
}
