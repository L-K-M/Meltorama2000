import SwiftUI
import AppKit
import MeltoramaCore

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                toolPalette.frame(minWidth: 142, idealWidth: 158, maxWidth: 200)
                VStack(spacing: 0) {
                    if session.hasPhoto {
                        HStack(spacing: 12) {
                            Text(L(session.mode == .brush ? session.tool.title : session.mode.rawValue)).font(.headline)
                            if !session.live { Text(L("Frame Preview")).font(.caption).foregroundStyle(.secondary); Button(L("Edit Live")) { session.live = true; session.playing = false; session.requestRender() } }
                            if session.compareOriginal { Text(L("Original Photo")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if session.mode == .crop { Button(L("Cancel")) { session.cropRect = nil; session.mode = .brush }; Button(L("Apply Crop")) { session.applyCrop() }.disabled(session.cropRect == nil) }
                        }.padding(.horizontal, 16).frame(height: 40).background(.bar)
                        Divider()
                        CanvasView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        statusBar
                    } else { WelcomeView(session: session) }
                    if session.showTimeline { Divider(); GoovieTimelineView(session: session) }
                }.frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity)
                if session.showInspector { inspector.frame(minWidth: 250, idealWidth: 278, maxWidth: 340) }
            }
            if let progress = session.progress {
                Divider()
                HStack { ProgressView(value: progress).frame(width: 200); Text(LF("Exporting… %d%%",Int(progress*100))).monospacedDigit(); Spacer(); Button(L("Cancel")) { session.cancelExport() } }.padding(10)
            }
        }
        .tint(MacTheme.accent)
        .frame(minWidth: 820, minHeight: 500)
        .sheet(isPresented: $session.showExport) { ExportSheet(session: session) }
        .alert(L("Meltorama Could Not Complete That"), isPresented: .init(get:{session.error != nil},set:{if !$0 {session.error = nil}})) { Button(L("OK")) { session.error = nil } } message: { Text(session.error ?? "") }
    }
    private var toolPalette: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("TOOLS")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top,8)
                HStack(spacing: 6) {
                    modeButton(.brush, "paintbrush.pointed", "Brush tools")
                    modeButton(.lenses, "circle.dotted", "Place and select lenses")
                    modeButton(.crop, "crop", "Crop photo")
                    modeButton(.hand, "hand.raised", "Pan the workspace")
                }
                Divider()
                toolGroup("Drag", [.smear,.move,.smudge,.nudge,.comb,.fault,.echo,.whip])
                toolGroup("Hold", [.grow,.shrink,.vortex,.unwind,.melt,.smooth,.ungoo,.rewind])
                toolGroup("Paint & Place", [.fuse,.pond,.freeze,.pins])
                Divider()
                Button { session.dealGoo() } label: { Label(L("Deal Goo"),systemImage:"dice") }.disabled(!session.hasPhoto)
                Button { session.confirmReset() } label: { Label(L("Reset Goo…"),systemImage:"arrow.counterclockwise") }.disabled(!session.hasPhoto)
            }.padding(.horizontal,12).padding(.bottom,12)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private func modeButton(_ mode: EditorSession.CanvasMode,_ symbol:String,_ label:String)->some View {
        Button { session.finishStroke(); session.mode = mode; session.requestRender() } label: { Image(systemName:symbol).frame(width:24,height:24) }
            .buttonStyle(.borderless).background(session.mode == mode ? MacTheme.accent.opacity(0.18) : .clear,in:RoundedRectangle(cornerRadius:5))
            .help(L(label)).accessibilityLabel(L(label)).accessibilityAddTraits(session.mode == mode ? .isSelected : [])
    }
    private func toolGroup(_ title:String,_ tools:[BrushTool])->some View {
        VStack(alignment:.leading,spacing:3) {
            Text(L(title)).font(.caption).foregroundStyle(.secondary)
            ForEach(tools,id:\.rawValue) { tool in
                Button { session.finishStroke(); session.tool = tool; session.mode = .brush; session.requestRender() } label: {
                    HStack(spacing:9) { Image(systemName:tool.symbol).frame(width:18); Text(L(tool.title)); Spacer() }.padding(.horizontal,7).frame(height:27).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .background(session.mode == .brush && session.tool == tool ? MacTheme.accent.opacity(0.2) : .clear,in:RoundedRectangle(cornerRadius:5))
                    .accessibilityLabel(L(tool.title))
                    .accessibilityAddTraits(session.tool == tool && session.mode == .brush ? .isSelected : [])
                    .help(L(tool.title))
            }
        }
    }
    private var statusBar: some View {
        HStack(spacing:12) {
            Text("\(Int(session.imageSize.width)) × \(Int(session.imageSize.height))").monospacedDigit()
            Text(session.hint).lineLimit(1).truncationMode(.tail).help(session.hint).foregroundStyle(.secondary)
            Spacer(minLength:4)
            Button(L("Fit")) {session.resetView()}.buttonStyle(.borderless)
            Text(Double(session.displayedZoom), format: .percent.precision(.fractionLength(session.displayedZoom < 0.01 ? 2 : 0)))
                .monospacedDigit().frame(minWidth:43)
        }.font(.caption).padding(.horizontal,12).frame(height:30).background(.bar)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                Text(L("INSPECTOR")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(14)
                if session.mode == .lenses { lensInspector }
                else if session.mode == .brush { brushInspector }
                else if session.mode == .crop {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Drag over the photo to choose its new frame. Cropping retains the original image.")).font(.callout).foregroundStyle(.secondary)
                        Button(L("Return to Full Photo")) { session.restoreFullPhoto() }.disabled(session.state.crop == nil)
                    }.padding(14)
                }
                Divider()
                VStack(alignment:.leading,spacing:8) {
                    Text(L("Whole Photo Effects")).font(.headline)
                    Text(L("Live adjustments, applied over your brush edits.")).font(.caption).foregroundStyle(.secondary)
                }.padding(14)
                ForEach(0..<6,id:\.self) { index in EffectSection(session:session,index:index) }
                Divider().padding(.top,8)
                VStack(alignment:.leading,spacing:10) {
                    HStack { Text(L("Fusion Photo")).font(.headline); Spacer(); Button {session.importFusion()} label:{Image(systemName:"plus").frame(width: 24, height: 24).contentShape(Rectangle())}.buttonStyle(.borderless).help(L("Add a Fusion photo")).accessibilityLabel(L("Add a Fusion photo")).disabled(!session.hasPhoto) }
                    if session.fusion != nil { Text(L("Paint the second photo through with Fusion.")).font(.caption).foregroundStyle(.secondary); Button(L("Remove Fusion Photo")) {session.setFusion(nil)} }
                    else { Text(L("Combine two photos with a soft brush.")).font(.caption).foregroundStyle(.secondary) }
                }.padding(14)
                Divider()
                VStack(alignment:.leading,spacing:10) {
                    Text(L("Document")).font(.headline)
                    Text(LF("%d stroke revisions · %d frames",session.state.log.revisions.filter {$0.stroke != nil}.count,session.state.keyframes.count)).font(.caption).foregroundStyle(.secondary)
                    Button(L("Save Project…")) {session.document?.save(nil)}.disabled(!session.hasPhoto)
                    Button(L("Export…")) {session.showExport=true}.disabled(!session.canExport)
                    if let message=session.exportMessage {Text(message).font(.caption).foregroundStyle(.secondary)}
                }.padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep native field suffixes clear when a persistent scroller appears.
            .padding(.trailing, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
        }.background(Color(nsColor:.controlBackgroundColor)).disabled(!session.hasPhoto)
    }
    private var brushInspector: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L(session.tool.title)).font(.headline)
            if session.tool != .pins {
                InspectorSlider(title:L("Size"),value:$session.radius,range:0.01...0.28,percent:true)
                InspectorSlider(title:L("Strength"),value:$session.strength,range:0.05...1,percent:true)
                Divider()
                Toggle(L("Mirror across center"),isOn:$session.mirrored)
                Picker(L("Kaleidoscope"),selection:$session.sectors) { ForEach([1,2,3,4,6,8,12],id:\.self) { Text($0 == 1 ? L("Off") : LF("%d sectors",$0)).tag($0) } }
                Toggle(L("Linked Portals"),isOn:$session.portalsEnabled)
                if session.portalsEnabled { Text(L("Click two rings, then paint through either.")).font(.caption).foregroundStyle(.secondary); Button(L("Place New Portals")) {session.portalPoints=[]} }
            } else { Text(L("Hold pins keep landmarks in place while you pull another point.")).font(.callout).foregroundStyle(.secondary); Text(LF("%d of 5 holds",session.holds.count)).font(.caption); InspectorSlider(title:L("Reach"),value:$session.pinReach,range:0.5...3); InspectorSlider(title:L("Rubber"),value:$session.pinRubber,range:0...1); Button(L("Clear Hold Pins")) {session.holds=[]} }
            if session.tool == .echo { Button(L("Choose New Echo Source")) {session.echoAnchor=nil}; Text(L("Option-click the photo to choose a source.")).font(.caption).foregroundStyle(.secondary) }
            if session.tool == .rewind { Button(L("Show Captured Frames")) {session.showTimeline=true} }
        }.padding(14)
    }
    private var lensInspector: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("Lenses")).font(.headline)
            Text(LF("%d of 4 placed",session.state.globals.lenses.count)).font(.caption).foregroundStyle(.secondary)
            if let index=session.selectedLens,session.state.globals.lenses.indices.contains(index) {
                Picker(L("Type"),selection:EditorBindings.lens(session:session,index:index,keyPath:\.type,fallback:.bulge,name:"Change Lens")) { ForEach(LensType.allCases,id:\.rawValue) {Text(L("Lens \($0.title)")).tag($0)} }
                InspectorSlider(title:L("Size"),value:EditorBindings.lens(session:session,index:index,keyPath:\.radius,fallback:0.18,name:"Resize Lens"),range:0.06...0.45,percent:true,onEditingChanged:{if $0 {session.beginContinuousEdit()} else {session.endContinuousEdit()}})
                InspectorSlider(title:L("Strength"),value:EditorBindings.lens(session:session,index:index,keyPath:\.strength,fallback:0,name:"Adjust Lens"),range:-1...1,percent:true,onEditingChanged:{if $0 {session.beginContinuousEdit()} else {session.endContinuousEdit()}})
                Button(L("Remove Lens"),role:.destructive) {session.edit("Remove Lens") {guard $0.globals.lenses.indices.contains(index) else {return};$0.globals.lenses.remove(at:index)};session.selectedLens=nil}
            } else { Text(L("Click the photo to place a lens. Click a lens to select it.")).font(.callout).foregroundStyle(.secondary) }
        }.padding(14)
    }

}

/// SwiftUI can read retained bindings after their inspector has disappeared.
/// Validate the captured selection at every read and write, rather than only
/// in the view's conditional branch, so delete/crop/undo cannot index stale UI.
enum EditorBindings {
    static func keyframeEasing(session: EditorSession, index: Int) -> Binding<Easing> {
        Binding(get: {
            guard session.selectedKeyframe == index, session.state.keyframes.indices.contains(index) else { return .linear }
            return session.state.keyframes[index].easing
        }, set: { value in
            guard session.selectedKeyframe == index, session.state.keyframes.indices.contains(index) else { return }
            session.edit("Change Easing") { state in
                guard state.keyframes.indices.contains(index) else { return }
                state.keyframes[index].easing = value
            }
        })
    }

    static func lens<Value>(session: EditorSession, index: Int, keyPath: WritableKeyPath<Lens, Value>,
                            fallback: Value, name: String) -> Binding<Value> {
        Binding(get: {
            guard session.selectedLens == index, session.state.globals.lenses.indices.contains(index) else { return fallback }
            return session.state.globals.lenses[index][keyPath: keyPath]
        }, set: { value in
            guard session.selectedLens == index, session.state.globals.lenses.indices.contains(index) else { return }
            session.edit(name) { state in
                guard state.globals.lenses.indices.contains(index) else { return }
                state.globals.lenses[index][keyPath: keyPath] = value
            }
        })
    }
}

struct InspectorSlider: View {
    let title:String
    @Binding var value:Float
    let range:ClosedRange<Float>
    var percent=false
    var onEditingChanged: ((Bool) -> Void)? = nil
    var body:some View {
        VStack(spacing:3) {
            HStack {Text(L(title));Spacer();InspectorNumericField(title: title, value: $value, range: range, percent: percent)}
            Slider(value:$value,in:range,onEditingChanged:{onEditingChanged?($0)}).accessibilityLabel(L(title))
        }.font(.callout).onDisappear {onEditingChanged?(false)}
    }
}

struct EffectSection: View {
    @ObservedObject var session:EditorSession
    let index:Int
    @State private var expanded=false
    @State private var previous:Float=0.35
    @State private var previousWobble=LeverWobble()
    private let titles=["Bulge","Twirl","Squeeze","Stretch","Spike","Static"]
    var value:Float { session.state.globals.values[index] }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:6) {
                Toggle(L(titles[index]),isOn:Binding(get:{value != 0 || !session.state.wobble.levers[index].isStill},set:{on in
                    if !on { previous=value; previousWobble=session.state.wobble.levers[index] }
                    session.edit("Toggle \(titles[index])") { $0.globals[index]=on ? previous : 0; $0.wobble.levers[index]=on ? previousWobble : LeverWobble() }
                })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel(LF("Enable %@",L(titles[index])))
                Button {expanded.toggle()} label:{
                    HStack(spacing: 6) {
                        Image(systemName:expanded ? "chevron.down" : "chevron.right").font(.system(size:10,weight:.semibold)).frame(width:12)
                        Text(L(titles[index])).font(.callout.weight(.medium))
                    }.frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(LF(expanded ? "Collapse %@" : "Expand %@",L(titles[index])))
                Spacer()
                if value != 0 { Text(String(format:"%+.0f%%",value*100)).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                Button {setValue(0);session.edit("Still \(titles[index])") {$0.wobble.levers[index]=LeverWobble()}} label:{Image(systemName:"arrow.counterclockwise").font(.caption).frame(width: 24, height: 24).contentShape(Rectangle())}.buttonStyle(.borderless).help(LF("Reset %@",L(titles[index]))).accessibilityLabel(LF("Reset %@",L(titles[index])))
            }.frame(height:29).padding(.horizontal,14)
            if expanded {
                VStack(alignment:.leading,spacing:8) {
                    InspectorSlider(title:L("Amount"),value:Binding(get:{value},set:setValue),range:-1...1,percent:true,onEditingChanged:{if $0 {session.beginContinuousEdit()} else {session.endContinuousEdit()}})
                    DisclosureGroup(L("Animate this effect")) {
                        VStack(spacing:8) {
                            Picker(L("Cycles per loop"),selection:Binding(get:{session.state.wobble.levers[index].rate},set:{rate in session.edit("Animate \(titles[index])") {$0.wobble.levers[index].rate=rate;if rate>0 && $0.wobble.levers[index].depth==0 {$0.wobble.levers[index].depth=0.35}}})) {ForEach(0..<9,id:\.self){Text($0==0 ? L("Off") : "\($0)").tag($0)}}
                            InspectorSlider(title:L("Depth"),value:Binding(get:{session.state.wobble.levers[index].depth},set:{depth in session.edit("Animation Depth") {$0.wobble.levers[index].depth=depth}}),range:0...1,percent:true,onEditingChanged:{if $0 {session.beginContinuousEdit()} else {session.endContinuousEdit()}})
                        }.padding(.top,6)
                    }.font(.caption)
                }.padding(.horizontal,18).padding(.top,5).padding(.bottom,12)
            }
        }
    }
    func setValue(_ value:Float) {session.edit("Adjust \(titles[index])") {$0.globals[index]=value}}
}

struct ExportSheet:View {
    @ObservedObject var session:EditorSession
    @State private var format:ExportFormat = .png
    @State private var quality=0.95
    @State private var speed:MovieSpeed = .normal
    @State private var loop=true
    @State private var limit=0
    private var options: ExportOptions { ExportOptions(format:format,jpegQuality:quality,speed:speed,loop:loop,maxDimension:limit==0 ? nil : limit) }
    private var needsFrames: Bool { format.isMovie && session.state.keyframes.count<2 }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("Export")).font(.title2.weight(.semibold))
            Picker(L("Format"),selection:$format) {ForEach(ExportFormat.allCases){Text(L($0.title)).tag($0)}}
            if format == .jpeg {HStack {Text(L("Quality"));Slider(value:$quality,in:0.1...1);Text("\(Int(quality*100))%").monospacedDigit()}}
            if format.isMovie {
                Picker(L("Speed"),selection:$speed) {ForEach(MovieSpeed.allCases,id:\.rawValue){Text(L($0.title)).tag($0)}}
                if format == .gif { Toggle(L("Loop forever"),isOn:$loop) }
                if session.state.keyframes.count<2 {Text(L("Capture at least two frames to export a GOOvie.")).foregroundStyle(.secondary)}
            } else {
                Picker(L("Size"),selection:$limit) {Text(L("Original resolution")).tag(0);Text(L("Up to 4096 pixels")).tag(4096);Text(L("Up to 2048 pixels")).tag(2048)}
                Text(LF("%d × %d source pixels. Export replays your edits against the original photo.",Int(session.imageSize.width),Int(session.imageSize.height))).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button(L("Share…")) {session.share(options:options)}.disabled(!session.canShare || needsFrames)
                Spacer()
                Button(L("Cancel")) {session.showExport=false}.keyboardShortcut(.cancelAction)
                Button(L("Export…")) {session.export(options:options)}.keyboardShortcut(.defaultAction).disabled(!session.canExport || needsFrames)
            }
        }.padding(24).frame(width:420).tint(MacTheme.accent)
    }
}
