import AppKit
import Foundation
let destination=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
func icon(_ size:Int)throws->Data {
    // Draw into an explicit size×size bitmap so the pixel dimensions follow the file name on any display, including Retina ones where lockFocus would render at twice the requested size.
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let context=NSGraphicsContext(bitmapImageRep:bitmap) else{fatalError("Missing graphics context")}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    let ctx=context.cgContext
    ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    ctx.setShadow(offset:CGSize(width:0,height:-18),blur:30,color:NSColor.black.withAlphaComponent(0.3).cgColor)
    let background=CGPath(roundedRect:CGRect(x:66,y:66,width:892,height:892),cornerWidth:188,cornerHeight:188,transform:nil)
    ctx.addPath(background);ctx.setFillColor(NSColor(red:0.08,green:0.09,blue:0.17,alpha:1).cgColor);ctx.fillPath();ctx.setShadow(offset:.zero,blur:0,color:nil)
    ctx.saveGState();ctx.addPath(background);ctx.clip()
    let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(red:0.12,green:0.75,blue:0.78,alpha:0.8).cgColor,NSColor(red:0.46,green:0.25,blue:0.85,alpha:0.7).cgColor,NSColor(red:0.08,green:0.09,blue:0.17,alpha:1).cgColor] as CFArray,locations:[0,0.5,1])!
    ctx.drawLinearGradient(gradient,start:CGPoint(x:140,y:950),end:CGPoint(x:880,y:100),options:[])
    ctx.restoreGState()
    ctx.addPath(background);ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor);ctx.setLineWidth(3);ctx.strokePath()
    // Illuminated stage bars above an original five-key keyboard mark.
    for (i,height) in [92,154,208,154,92].enumerated(){
        let x=CGFloat(214+i*124)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.addPath(CGPath(roundedRect:CGRect(x:x,y:614,width:72,height:CGFloat(height)),cornerWidth:34,cornerHeight:34,transform:nil));ctx.fillPath()
    }
    let keyColors=[NSColor(red:0.90,green:0.95,blue:1,alpha:1),NSColor.white]
    for i in 0..<5 {
        ctx.setFillColor(keyColors[i%2].cgColor)
        ctx.addPath(CGPath(roundedRect:CGRect(x:CGFloat(174+i*138),y:206,width:124,height:340),cornerWidth:22,cornerHeight:22,transform:nil));ctx.fillPath()
    }
    for i in [0,1,3] {
        ctx.setShadow(offset:CGSize(width:0,height:-5),blur:8,color:NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setFillColor(NSColor(red:0.10,green:0.11,blue:0.19,alpha:1).cgColor)
        ctx.addPath(CGPath(roundedRect:CGRect(x:CGFloat(263+i*138),y:364,width:82,height:184),cornerWidth:15,cornerHeight:15,transform:nil));ctx.fillPath();ctx.setShadow(offset:.zero,blur:0,color:nil)
    }
    context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
    guard let png=bitmap.representation(using:.png,properties:[:]) else{fatalError("PNG encoding failed")}
    return png
}
for size in [16,32,128,256,512] {
    try icon(size).write(to:destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size*2).write(to:destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
