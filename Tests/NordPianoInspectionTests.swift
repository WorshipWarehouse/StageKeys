import Foundation
@main struct NordPianoInspectionTests {
 static func main()throws {
  // Anchor the test's own CRC with the standard check value so the fixtures do
  // not merely agree with the reader under test.
  func crc(_ bytes:[UInt8])->UInt32 {
   var table:[UInt32]=(0..<256).map{index->UInt32 in var value=UInt32(index);for _ in 0..<8 {value=(value&1)==1 ? 0xEDB88320^(value>>1):value>>1};return value}
   var value:UInt32=0xFFFFFFFF
   for byte in bytes {value=table[Int((value^UInt32(byte))&0xff)]^(value>>8)}
   return value^0xFFFFFFFF
  }
  assert(crc(Array("123456789".utf8))==0xCBF43926,"CRC32 must match the standard check value")
  func le32(_ value:UInt32)->[UInt8] {[UInt8(value&0xff),UInt8((value>>8)&0xff),UInt8((value>>16)&0xff),UInt8((value>>24)&0xff)]}
  func put(_ value:UInt16,_ bytes:inout [UInt8],_ offset:Int){bytes[offset]=UInt8(value>>8);bytes[offset+1]=UInt8(value&0xff)}
  func putText(_ text:String,_ bytes:inout [UInt8],_ offset:Int,_ length:Int) {
   let raw=Array(text.utf8);for i in 0..<min(raw.count,length){bytes[offset+i]=raw[i]}
  }
  // A synthetic body: documented prefix, one stroke record, zero alignment gap,
  // then whole encoded blocks. No vendor content is involved.
  func body(stream:UInt16=0x464,channels:UInt16=2,strokes:Int=1,audioBlocks:Int=1,declaredCount:Int?=nil,audioExtra:Int=0)->[UInt8] {
   var bytes=[UInt8](repeating:0,count:0x732)
   putText("CNSP",&bytes,0,4)
   put(stream,&bytes,0x04)
   bytes[0x06]=0x11;bytes[0x07]=0x22;bytes[0x08]=0x33;bytes[0x09]=0x44
   putText("Astoria Grand#XL",&bytes,0x1c,32)
   putText("Astoria Grand",&bytes,0x3c,32)
   putText("XL",&bytes,0x5c,32)
   for key in 0..<128 {bytes[0x8c+key]=0xFF}
   for key in 60..<65 {bytes[0x8c+key]=60}
   put(stream,&bytes,0x61c)
   put(channels,&bytes,0x61e)
   put(UInt16(strokes),&bytes,0x620)
   // Root 60 carries every declared stroke; the rest are empty.
   let rootCount=UInt16(declaredCount ?? strokes)
   put(rootCount,&bytes,0x622+60*2)
   bytes+=[UInt8](repeating:0,count:118*strokes)
   let block=1022*Int(channels)
   let start=192+((bytes.count-192+block-1)/block)*block
   bytes+=[UInt8](repeating:0,count:start-bytes.count)
   bytes+=[UInt8](repeating:0x5a,count:block*audioBlocks+audioExtra)
   return bytes
  }
  func container(_ payload:[UInt8],generation:UInt32=1,tag:String="npno",crcOverride:UInt32?=nil)->Data {
   var bytes=Array("CBIN".utf8)
   bytes+=le32(generation)
   bytes+=Array(tag.utf8)
   bytes+=le32(0) // location: not interpreted for a piano library
   bytes+=le32(0) // aux: not interpreted for a piano library
   bytes+=le32(6100) // content version
   if generation==1 {
    bytes+=le32(crcOverride ?? crc(payload))
    bytes+=[UInt8](repeating:0,count:16)
    bytes+=payload
   } else {
    bytes+=payload
    bytes+=[0,0] // inferred crc16 trailer, deliberately not validated
   }
   return Data(bytes)
  }
  func rejects(_ data:Data,_ expected:NordPiano.Problem,file:String=#file,line:UInt=#line) {
   do {_ = try NordPiano.inspect(data);fatalError("\(file):\(line): accepted invalid input instead of \(expected)")}
   catch let problem as NordPiano.Problem {assert(problem==expected,"\(file):\(line): \(problem) is not \(expected)")}
   catch {fatalError("\(file):\(line): unexpected error \(error)")}
  }

  let valid=container(body())
  let unchanged=valid
  let report=try NordPiano.inspect(valid)
  assert(valid==unchanged,"Inspection must not modify the input bytes")
  assert(report.generation==1 && report.contentVersion==6100 && report.streamVersion==0x464)
  assert(report.name=="Astoria Grand" && report.variant=="XL" && report.voicing=="XL")
  assert(report.channels==2 && report.strokes==1 && report.coveredKeys==5)
  assert(report.directoryEnd==0x732+118 && report.audioBlockBytes==2044)
  assert(report.audioStart==2236 && report.audioBytes==2044,"Aligned audio start and one whole block")
  assert(report.audioStart % 2044==192,"The audio grid is offset from whole blocks by 192 bytes")
  if case .verified = report.checksum {} else {fatalError("A correct container checksum must verify: \(report.checksum)")}
  assert(report.notes.contains{$0.contains("Inspection only")} && report.notes.contains{$0.contains("not labelled playable")})
  assert(report.notes.contains{$0.contains("not validated yet")},"Per-stroke spans stay explicitly unverified")

  // A checksum problem is reported for review, not silently treated as a pass.
  var damaged=Array(valid);damaged[damaged.count-1]^=0xff
  let damagedReport=try NordPiano.inspect(Data(damaged))
  if case .mismatch(let stored,let computed)=damagedReport.checksum {assert(stored != computed)} else {fatalError("A changed body must not verify")}
  assert(damagedReport.notes.contains{$0.contains("does not match")})

  var wrongMagic=Array(valid);wrongMagic[0]=0x41
  rejects(Data(wrongMagic),.badMagic)
  rejects(container(body(),tag:"nsmp"),.wrongFormatTag("nsmp"))
  rejects(container(body(),generation:2),.unsupportedGeneration(2))
  rejects(Data(valid.prefix(0x20)),.truncatedHeader(bytes:0x20,minimum:0x2c))
  rejects(container(Array(body().prefix(0x700))),.bodyTooSmall(bytes:0x700,minimum:0x732))
  rejects(container(body(stream:0x451)),.unsupportedStreamVersion(0x451))
  rejects(container(body(channels:3)),.invalidChannelCount(3))
  rejects(container(body(strokes:0)),.invalidStrokeCount(0))
  rejects(container(body(declaredCount:2)),.strokeCountMismatch(table:2,declared:1))

  var echo=body();put(0x450,&echo,0x61c)
  rejects(container(echo),.streamVersionEchoMismatch(echo:0x450,stream:0x464))

  var shortDirectory=body(strokes:2)
  shortDirectory=[UInt8](shortDirectory.prefix(0x732+118))
  rejects(container(shortDirectory),.directoryOverflow(end:0x732+236,bodyBytes:0x732+118))

  var gap=body();gap[0x732+118]=1
  rejects(container(gap),.nonZeroAlignmentGap(offset:0x732+118))

  rejects(container(body(audioExtra:1)),.audioNotBlockAligned(bytes:2045,block:2044))
  rejects(container(Array(body().prefix(0x732+118))),.audioGridOutsideBody(start:2236,bodyBytes:0x732+118))

  // Padding after the terminator is part of the fixed field, so a control byte
  // there is reported instead of returning a truncated name; a space is padding.
  var controlPadding=body();controlPadding[0x1c+17]=0x01
  rejects(container(controlPadding),.invalidText(offset:0x1c))
  var spacePadding=body();spacePadding[0x1c+17]=0x20
  let spacedReport=try NordPiano.inspect(container(spacePadding))
  assert(spacedReport.name.contains("Astoria Grand"))

  // Limits are enforced before any payload work, through both entrypoints.
  do {_ = try NordPiano.inspect(valid,limits:.init(maximumFileBytes:100,maximumStrokes:4096));fatalError("Oversized file accepted")}
  catch let problem as NordPiano.Problem {assert(problem == .fileTooLarge(bytes:valid.count,maximum:100))}
  do {_ = try NordPiano.inspect(container(body(strokes:2)),limits:.init(maximumFileBytes:1<<20,maximumStrokes:1));fatalError("Stroke limit ignored")}
  catch let problem as NordPiano.Problem {assert(problem == .invalidStrokeCount(2))}

  let raw=[UInt8](valid)
  do {
   _ = try raw.withUnsafeBytes { (buffer:UnsafeRawBufferPointer) -> NordPiano.Report in
    try NordPiano.inspect(buffer,limits:.init(maximumFileBytes:100,maximumStrokes:4096))
   }
   fatalError("Oversized raw buffer accepted")
  } catch let problem as NordPiano.Problem {assert(problem == .fileTooLarge(bytes:valid.count,maximum:100))}

  let legacy=try NordPiano.inspect(container(body(),generation:0))
  assert(legacy.generation==0 && legacy.checksum == .unestablished)
  assert(legacy.notes.contains{$0.contains("Type-0")},"An unverifiable checksum must say so")

  let mono=try NordPiano.inspect(container(body(channels:1)))
  assert(mono.channels==1 && mono.audioBlockBytes==1022)
  let legacyStream=try NordPiano.inspect(container(body(stream:0x450)))
  assert(legacyStream.voicing==nil,"Only 0x464 streams carry a voicing")

  print("PASS: bounded .npno container preflight, checksum reporting, limits and malformed-input rejection",report.name,report.audioStart,report.audioBytes)
 }
}
