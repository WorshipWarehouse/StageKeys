import Foundation
import CryptoKit

/// Streaming content identity for original instruments, samples and library packs.
enum AssetDigest {
    static func sha256(_ url:URL)throws->String {
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var hash=SHA256()
        while let bytes=try handle.read(upToCount:1024*1024),!bytes.isEmpty{hash.update(data:bytes)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
