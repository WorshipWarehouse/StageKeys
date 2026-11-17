import Foundation
@main struct NordPianoDecodeTests {
 static func main() throws {
  func request(_ data:Data,frames:Int,blocks:Int=1,seeds:[[Int64]]=[[0,0,0,0],[0,0,0,0]])->NordPiano.Stroke {
   .init(root:60,bank:0,layer:0,threshold:0,frames:frames,blocks:blocks,offset:0,seeds:seeds,loopStart:0,loopEnd:0,trim:0,noteOffFade:0)
  }
  // Independent bit-position writer: no reservoir or decoder recurrence.
  func block(width:Int,order:Int,channels:Int,values:[Int])->Data {
   var words=[UInt16](repeating:0,count:511*channels)
   words[0]=UInt16(width | (order<<5))
   for (i,value) in values.enumerated() {
    let bits=UInt16(truncatingIfNeeded:value)
    for bit in 0..<width where bits & (1<<bit) != 0 {
     let position=i*width+bit;words[1+position/16] |= 1<<(position%16)
    }
   }
   return Data(words.flatMap{[UInt8($0>>8),UInt8($0&255)]})
  }
  func rejects(_ action:()throws->Void){do{try action();fatalError("Accepted malformed stroke")}catch{}}
  for channels in 1...2 {
   for width in [1,3,7,8,13,16] {
    let frames=(1022*channels-2)*8/(width*channels),owned=frames-64
    let values=(0..<frames*channels).map{ $0%2==0 ? 0:-1 }
    let bytes=block(width:width,order:0,channels:channels,values:values)
    let pcm=try NordPiano.decode(bytes,stroke:request(bytes,frames:owned),channels:channels)
    assert(pcm==values.prefix(owned*channels).map(Int16.init))
    let repeated = try NordPiano.decode(bytes,stroke:request(bytes,frames:owned),channels:channels)
    assert(pcm == repeated)
   }
  }
  let frames=1020*8/8,owned=frames-64
  for order in 1...4 {
   // Constant initial history and zero residuals remain constant for every order.
   let bytes=block(width:8,order:order,channels:1,values:Array(repeating:0,count:frames))
   let pcm=try NordPiano.decode(bytes,stroke:request(bytes,frames:owned,seeds:[[123,123,123,123],[0,0,0,0]]),channels:1)
   assert(pcm.allSatisfy{$0==123})
  }
  for order in 0...4 {
   let count=1020*8/16
   func sample(_ n:Int)->Int {let x=(n%9+9)%9;return x*x*x-256}
   func difference(_ n:Int,_ order:Int)->Int {order==0 ? sample(n):difference(n,order-1)-difference(n-1,order-1)}
   let raw=block(width:16,order:order,channels:1,values:(0..<count).map{difference($0,order)})
   let initial=(-4 ..< 0).map{Int64(sample($0))}
   let out=try NordPiano.decode(raw,stroke:request(raw,frames:count-64,seeds:[initial,[0,0,0,0]]),channels:1)
   assert(out == (0..<count-64).map{Int16(sample($0))})
  }
  let bytes=block(width:8,order:1,channels:1,values:Array(repeating:3,count:frames))
  let pcm=try NordPiano.decode(bytes,stroke:request(bytes,frames:owned,seeds:[[0,0,0,100],[0,0,0,0]]),channels:1)
  assert(Array(pcm.prefix(4)) == [103,106,109,112])
  let first=block(width:8,order:0,channels:1,values:(0..<frames).map{$0%61-30})
  let second=block(width:8,order:0,channels:1,values:(0..<frames).map{($0+owned)%61-30})
  let joined=first+second
  let decoded=try NordPiano.decode(joined,stroke:request(joined,frames:owned*2,blocks:2),channels:1)
  assert(decoded == (0..<owned*2).map{Int16($0%61-30)})
  rejects{_ = try NordPiano.decode(first+first,stroke:request(joined,frames:owned*2,blocks:2),channels:1)}
  rejects{_ = try NordPiano.decode(first,stroke:request(first,frames:owned-1),channels:1)}
  rejects{_ = try NordPiano.decode(first.dropLast(),stroke:request(first,frames:owned),channels:1)}
  rejects{_ = try NordPiano.decode(Data(repeating:0,count:1022),stroke:request(first,frames:owned),channels:1)}
  rejects{_ = try NordPiano.decode(bytes,stroke:request(bytes,frames:owned,seeds:[[32767,32767,32767,32767],[0,0,0,0]]),channels:1)}
  rejects{_ = try NordPiano.decode(bytes,stroke:request(bytes,frames:owned),channels:0)}
  rejects{_ = try NordPiano.decode(bytes,stroke:request(bytes,frames:owned),channels:1,cancelled:{true})}
  print("PASS Nord codec: widths, signed interleaving, predictors, exact overlap, bounds, clipping and cancellation")
 }
}
