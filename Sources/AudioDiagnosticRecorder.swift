import AVFoundation

/// Copies a bounded take from an output tap. File I/O runs on its own queue;
/// instrument samples and library presets are never opened for writing.
final class AudioDiagnosticRecorder {
    struct Summary { let url:URL; let frames:AVAudioFramePosition; let sampleRate:Double }
    private let queue=DispatchQueue(label:"studio.stagekeys.audio-check",qos:.userInitiated)
    private let lock=NSLock()
    private var accepting=true
    private var pending=0
    private var submitted:AVAudioFramePosition=0
    private let limit:AVAudioFramePosition
    private let format:AVAudioFormat
    private let url:URL
    private var file:AVAudioFile?
    private var failure:Error?
    private let completion:(Result<Summary,Error>)->Void

    init(url:URL,format:AVAudioFormat,seconds:Double=30,completion:@escaping(Result<Summary,Error>)->Void)throws {
        guard seconds.isFinite,seconds>0,seconds<=30,format.commonFormat == .pcmFormatFloat32,!format.isInterleaved,format.channelCount==2 else{throw CocoaError(.fileWriteUnknown)}
        self.url=url;self.format=format;self.limit=AVAudioFramePosition((format.sampleRate*seconds).rounded());self.completion=completion
        // A diagnostic take preserves the engine's rate and floating-point output.
        file=try AVAudioFile(forWriting:url,settings:format.settings,commonFormat:.pcmFormatFloat32,interleaved:false)
    }

    func append(_ buffer:AVAudioPCMBuffer) {
        lock.lock()
        guard accepting else{lock.unlock();return}
        guard buffer.format == format,buffer.frameLength>0,pending<32 else{
            lock.unlock();finish(error:NSError(domain:"StageKeysAudioCheck",code:1,userInfo:[NSLocalizedDescriptionKey:"The audio check could not keep up. No incomplete take should be used for comparison."]));return
        }
        let count=AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameLength),limit-submitted))
        guard count>0,let copy=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:count),let input=buffer.floatChannelData,let output=copy.floatChannelData else{lock.unlock();finish(error:CocoaError(.fileWriteUnknown));return}
        copy.frameLength=count
        for channel in 0..<Int(format.channelCount){memcpy(output[channel],input[channel],Int(count)*MemoryLayout<Float>.size)}
        pending+=1;submitted+=AVAudioFramePosition(count)
        let ended=submitted==limit
        // Schedule under the same lock as finish so every accepted block is
        // written before the file closes, including concurrent stop requests.
        queue.async { [self] in
            if failure==nil {do{try file?.write(from:copy)}catch{failure=error}}
            lock.lock();pending-=1;lock.unlock()
        }
        lock.unlock()
        if ended {finish()}
    }

    func finish(error:Error?=nil) {
        lock.lock();guard accepting else{lock.unlock();return};accepting=false
        let frames=submitted
        queue.async { [self] in
            let result:Result<Summary,Error>
            if let problem=error ?? failure {result = .failure(problem)}
            else {result = .success(Summary(url:url,frames:frames,sampleRate:format.sampleRate))}
            file=nil
            DispatchQueue.main.async {self.completion(result)}
        }
        lock.unlock()
    }
}
