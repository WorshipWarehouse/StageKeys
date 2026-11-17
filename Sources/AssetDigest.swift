import Foundation
import CryptoKit

/// Streaming content identity for original instruments, samples and library packs.
enum AssetDigest {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Hashes at most `byteCount` bytes from the handle's current position and
    /// reports how many it read, so a caller can refuse an input that changed.
    static func sha256(_ handle:FileHandle,byteCount:Int)throws->(digest:String,read:Int) {
        var hash=SHA256()
        var remaining=byteCount
        var read=0
        while remaining > 0 {
            let bytes=try handle.read(upToCount:min(remaining,1024*1024)) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data:bytes)
            remaining-=bytes.count
            read+=bytes.count
        }
        return (hash.finalize().map{String(format:"%02x",$0)}.joined(),read)
    }
    static func sha256(_ url:URL)throws->String {
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var hash=SHA256()
        while let bytes=try handle.read(upToCount:1024*1024),!bytes.isEmpty{hash.update(data:bytes)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
