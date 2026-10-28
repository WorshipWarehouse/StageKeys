import AppKit
import Foundation
import ImageIO
guard CommandLine.arguments.count >= 2 else{fatalError("Usage: GenerateAppIcon ICONSET-DIRECTORY [iOS-APP-ICON.png]")}
let destination=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
// One 1024-point composition, scaled to each output size. The macOS icon is a rounded square
// with a drop shadow on a transparent margin; iOS masks its own corners and forbids an alpha
// channel, so that variant fills the canvas and is drawn RGB.
func draw(_ ctx:CGContext,size:Int,fullBleed:Bool){
    ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    let background=fullBleed ? CGRect(x:0,y:0,width:1024,height:1024) : CGRect(x:66,y:66,width:892,height:892)
    let outline=CGPath(roundedRect:background,cornerWidth:fullBleed ? 0:188,cornerHeight:fullBleed ? 0:188,transform:nil)
    if !fullBleed {ctx.setShadow(offset:CGSize(width:0,height:-18),blur:30,color:NSColor.black.withAlphaComponent(0.3).cgColor)}
    ctx.addPath(outline);ctx.setFillColor(NSColor(red:0.08,green:0.09,blue:0.17,alpha:1).cgColor);ctx.fillPath();ctx.setShadow(offset:.zero,blur:0,color:nil)
    ctx.saveGState();ctx.addPath(outline);ctx.clip()
    let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(red:0.12,green:0.75,blue:0.78,alpha:0.8).cgColor,NSColor(red:0.46,green:0.25,blue:0.85,alpha:0.7).cgColor,NSColor(red:0.08,green:0.09,blue:0.17,alpha:1).cgColor] as CFArray,locations:[0,0.5,1])!
    // Beyond the gradient's start and end the canvas keeps the background colour. The macOS
    // rounded corner cuts that region away, so only the full-bleed variant has to extend it.
    ctx.drawLinearGradient(gradient,start:CGPoint(x:140,y:950),end:CGPoint(x:880,y:100),options:fullBleed ? [.drawsBeforeStartLocation,.drawsAfterEndLocation] : [])
    ctx.restoreGState()
    if !fullBleed {
        ctx.addPath(outline);ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor);ctx.setLineWidth(3);ctx.strokePath()
    }
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
}
func png(_ size:Int)throws->Data {
    // An explicit size×size bitmap follows the file name on any display, where lockFocus would
    // render at the backing scale and double every dimension on a Retina screen.
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let context=NSGraphicsContext(bitmapImageRep:bitmap) else{fatalError("Missing graphics context")}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    draw(context.cgContext,size:size,fullBleed:false)
    context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
    guard let data=bitmap.representation(using:.png,properties:[:]) else{fatalError("PNG encoding failed")}
    return data
}
func appIconPNG(_ size:Int)throws->Data {
    // An iOS icon is a full-bleed opaque square that the system masks, and it may carry no alpha
    // channel at all. Draw with the iconset's own compositing, then flatten the result to RGB.
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let context=NSGraphicsContext(bitmapImageRep:bitmap) else{fatalError("Missing graphics context")}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    draw(context.cgContext,size:size,fullBleed:true)
    context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
    guard let drawn=bitmap.cgImage else{fatalError("Missing rendered image")}
    var pixels=[UInt8](repeating:0,count:size*size*4), rendered:CGImage?
    pixels.withUnsafeMutableBytes { raw in
        guard let flat=CGContext(data:raw.baseAddress,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{fatalError("Missing graphics context")}
        flat.draw(drawn,in:CGRect(x:0,y:0,width:size,height:size))
        rendered=flat.makeImage()
    }
    guard let image=rendered else{fatalError("Missing rendered image")}
    let data=NSMutableData()
    guard let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else{fatalError("PNG encoding failed")}
    CGImageDestinationAddImage(destination,image,nil)
    guard CGImageDestinationFinalize(destination) else{fatalError("PNG encoding failed")}
    return data as Data
}
for size in [16,32,128,256,512] {
    try png(size).write(to:destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size*2).write(to:destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    let icon=URL(fileURLWithPath:CommandLine.arguments[2])
    try FileManager.default.createDirectory(at:icon.deletingLastPathComponent(),withIntermediateDirectories:true)
    try appIconPNG(1024).write(to:icon)
}
