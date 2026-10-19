import Foundation
@main struct EXSReferenceIdentityTests {
 static func main()throws {
  func zone(_ group:UInt32,_ sample:UInt32)->EXSNative.Chunk {var b=[UInt8](repeating:0,count:96);for (offset,value) in [(88,group),(92,sample)]{for i in 0..<4{b[offset+i]=UInt8(truncatingIfNeeded:value >> (i*8))}};return .init(kind:1,modern:false,index:0,name:"Zone",body:b)}
  let samples=[EXSNative.Chunk(kind:3,modern:false,index:0,name:"low.wav",body:[]),.init(kind:3,modern:false,index:0,name:"high.wav",body:[])]
  let groups=[EXSNative.Chunk(kind:2,modern:false,index:0,name:"Legato",body:[]),.init(kind:2,modern:false,index:1,name:"Staccato",body:[]),.init(kind:2,modern:false,index:3,name:"Release",body:[])]
  let source=samples+groups+[zone(0,0),zone(2,1)],mapped=try EXSNative.referenceIdentities(source)
  assert(mapped.filter{$0.kind==3}.map(\.index)==[0,1]);assert(mapped.filter{$0.kind==2}.map(\.index)==[0,1,2]);assert(mapped.filter{$0.kind==3}.map(\.name)==samples.map(\.name));assert(source[1].index==0 && source[4].index==3)
  var modern=source;for i in modern.indices{modern[i].modern=true};let retained=try EXSNative.referenceIdentities(modern);assert(retained[1].index==0 && retained[4].index==3,"Modern IDs must never be repaired as legacy ordinals")
  do{_ = try EXSNative.referenceIdentities(samples+[zone(0xffffffff,3)]);fatalError("Invalid ordinal accepted")}catch{}
  func chunk(_ signature:UInt32,_ size:UInt32,_ body:[UInt8])->Data {var d=Data(repeating:0,count:84);for (offset,value) in [(0,signature),(4,size)]{for i in 0..<4{d[offset+i]=UInt8(truncatingIfNeeded:value >> (i*8))}};d.replaceSubrange(16..<20,with:Data("JBOS".utf8));d.append(contentsOf:body);return d}
  let body=[UInt8](repeating:0,count:96),flagged=chunk(0x81000101,0x8060,body),decoded=try EXSNative.chunks(flagged)
  assert(decoded.count==1 && decoded[0].kind==1 && decoded[0].body.count==96)
  let ordinary=try EXSNative.chunks(chunk(0x01000101,96,body));assert(ordinary[0].body==decoded[0].body)
  do{_ = try EXSNative.chunks(chunk(0x81000101,0x8061,body));fatalError("Truncated encoded size accepted")}catch{}
  print("PASS: legacy sample/group ordinal references, immutable input, modern identity preservation and invalid-reference refusal")
 }
}
