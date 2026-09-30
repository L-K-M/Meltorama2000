// Reuses the repository's hand-authored Android droplet vector in a Mac icon.
import AppKit
import Foundation

let destination=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
func color(_ rgb:UInt32,_ alpha:CGFloat=1)->NSColor {NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)}
func path(_ start:CGPoint,_ curves:[(CGPoint,CGPoint,CGPoint)],_ fill:NSColor) {
    let p=NSBezierPath();p.move(to:start)
    for (a,b,c) in curves {p.curve(to:c,controlPoint1:a,controlPoint2:b)}
    p.close();fill.setFill();p.fill()
}
func p(_ x:CGFloat,_ y:CGFloat)->CGPoint {CGPoint(x:x,y:y)}
for size in [16,32,64,128,256,512,1024] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let context=NSGraphicsContext(bitmapImageRep:bitmap)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    context.cgContext.translateBy(x:0,y:CGFloat(size));context.cgContext.scaleBy(x:CGFloat(size)/108,y:-CGFloat(size)/108)
    let background=NSBezierPath(roundedRect:NSRect(x:5,y:5,width:98,height:98),xRadius:23,yRadius:23)
    NSGradient(starting:color(0x30384c),ending:color(0x080a16))!.draw(in:background,angle:45)
    let bezel=NSBezierPath(ovalIn:NSRect(x:20,y:20,width:68,height:68))
    NSGradient(colors:[color(0xf2f7ff),color(0x9dafd2),color(0x4a5678),color(0xa9badb),color(0xe8f0fc)])!.draw(in:bezel,angle:45)
    color(0x1e2540).setFill();NSBezierPath(ovalIn:NSRect(x:24,y:24,width:60,height:60)).fill()
    color(0x080a16).setFill();NSBezierPath(ovalIn:NSRect(x:26,y:26,width:56,height:56)).fill()
    color(0x35e3f2,0.8).setFill();NSRect(x:28,y:66,width:52,height:2).fill()
    path(p(54,32),[(p(64,32),p(71,39),p(71,48)),(p(71,56),p(66,60),p(67,66)),(p(68,73),p(61,78),p(53,78)),(p(45,78),p(39,74),p(40,67)),(p(41,60),p(37,56),p(37,48)),(p(37,39),p(44,32),p(54,32))],color(0xff3d9e))
    path(p(46,74),[(p(49,74),p(50,78),p(49,82)),(p(48,85),p(45,85),p(44,82)),(p(43,79),p(43,74),p(46,74))],color(0xff3d9e))
    path(p(67,58),[(p(67,66),p(62,74),p(53,75)),(p(45,76),p(40,72),p(40,67)),(p(44,72),p(49,73),p(55,71)),(p(61,69),p(65,64),p(67,58))],color(0xc42a78))
    path(p(46,40),[(p(51,37),p(58,37),p(62,40)),(p(65,42),p(62,45),p(57,45)),(p(52,45),p(48,46),p(46,45)),(p(43,44),p(43,41),p(46,40))],color(0xffffff,0.72))
    NSGraphicsContext.restoreGraphicsState()
    let data=bitmap.representation(using:.png,properties:[:])!
    if size<=512 {try data.write(to:destination.appendingPathComponent("icon_\(size)x\(size).png"))}
    if size>=32 {try data.write(to:destination.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}
