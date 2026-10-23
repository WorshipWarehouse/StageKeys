import AVFoundation

final class OutputMeter {
    struct Reading {
        var peak:Float=0,rms:Float=0
        var frames:UInt64=0,invalid:UInt64=0,overload:UInt64=0
        var peakDB:Float {peak>0 ? 20*log10(peak): -120}
        var rmsDB:Float {rms>0 ? 20*log10(rms): -120}
    }
    private let meter=sk_output_meter_create()!
    func append(_ buffer:AVAudioPCMBuffer) {
        guard let channels=buffer.floatChannelData,buffer.format.channelCount==2 else{return}
        sk_output_meter_process(meter,channels[0],channels[1],buffer.frameLength)
    }
    func read()->Reading {
        var r=Reading();sk_output_meter_read(meter,&r.peak,&r.rms,&r.frames,&r.invalid,&r.overload);return r
    }
    deinit{sk_output_meter_destroy(meter)}
}

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

/// Opt-in fixed calibration. This measures an isolated graph, never the live mix.
enum InstrumentGainMatch {
    struct Result:Equatable {
        let rmsDB:Double
        let peakDB:Double
        let trimDB:Float
        let peakLimited:Bool
        let targetDB:Double
        var outputRMSDB:Double {rmsDB+Double(trimDB)}
        var trimLimited:Bool {abs(outputRMSDB-targetDB)>0.01 && !peakLimited}
    }
    static func recommendation(rms:Double,peak:Double,targetDB:Double = -24,ceilingDB:Double = -9)throws->Result {
        guard rms.isFinite,peak.isFinite,rms>0.00001,peak>=rms,targetDB.isFinite,(-60 ... -6).contains(targetDB),ceilingDB.isFinite,(-24 ... -1).contains(ceilingDB) else{throw failure("No usable calibration signal. Check the instrument's playable range and preset.")}
        let rmsDB=20*log10(rms),peakDB=20*log10(peak),wanted=targetDB-rmsDB,allowed=ceilingDB-peakDB
        guard allowed >= -24 else{throw failure("The instrument output exceeds the calibration trim range. Lower its output and retry.")}
        return Result(rmsDB:rmsDB,peakDB:peakDB,trimDB:Float(max(-24,min(12,min(wanted,allowed)))),peakLimited:allowed<min(wanted,12),targetDB:targetDB)
    }
    static func retarget(_ result:Result,to targetDB:Double)throws->Result {
        try recommendation(rms:pow(10,result.rmsDB/20),peak:pow(10,result.peakDB/20),targetDB:targetDB)
    }
    private static func failure(_ message:String)->NSError {NSError(domain:"StageKeysGainMatch",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    @MainActor static func measure(_ original:Layer,modulation:Float,targetDB:Double = -24,tempo:Double = 72)async throws->Result {
        guard original.loaded,original.midiDestinationID==nil else{throw failure("External MIDI devices cannot be measured by the app's audio engine.")}
        guard tempo.isFinite,(20...300).contains(tempo),targetDB.isFinite,(-60 ... -6).contains(targetDB) else{throw failure("Choose a valid target level and patch tempo before measuring.")}
        var layer=original;layer.gain=1;layer.muted=false;layer.channelSettings.outputTrimDB=nil
        let audio=AudioController();var loadError:String?
        audio.onError={loadError=$0};defer{audio.stop()}
        try audio.prepareOffline();audio.bypassMasterLimiter(true);audio.master(1);audio.space(0)
        audio.clock(tempo,false);audio.modulation(0,value:modulation);audio.configure(0,layer);audio.gain(0,1,seconds:0)
        if layer.external != nil {
            for _ in 0..<500 {
                try Task.checkCancellation()
                if let error=loadError{throw failure(error)}
                if audio.externalRack?.unit(channel:0) != nil{break}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            guard audio.externalRack?.unit(channel:0) != nil else{throw failure("The instrument did not finish loading for calibration.")}
        }
        var energy=0.0,count=0,peak=0.0,blocks=0
        func render(_ frames:Int,measure:Bool)async throws {
            var position=0
            while position<frames {
                try Task.checkCancellation()
                let buffer=try audio.offlineBlock()
                guard let data=buffer.floatChannelData else{throw failure("The instrument did not provide floating-point audio.")}
                for i in 0..<Int(buffer.frameLength) {
                    for c in 0..<Int(buffer.format.channelCount) {
                        let sample=Double(data[c][i]);guard sample.isFinite else{throw failure("The instrument produced invalid audio during calibration.")}
                        peak=max(peak,abs(sample))
                        if measure && position+i>=4800 && position+i<24000 {energy+=sample*sample;count+=1}
                    }
                }
                position+=Int(buffer.frameLength);blocks+=1
                if blocks%32==0 {await Task.yield()}
            }
        }
        try await render(4096,measure:false)
        let selected=[48,60,72].filter{(layer.low...layer.high).contains($0)}
        let notes=selected.isEmpty ? [(layer.low+layer.high)/2]:selected
        for note in notes {
            audio.noteOn(key:note,pitch:note,instrument:layer.instrument,layer:0,velocity:83.0/127)
            try await render(28800,measure:true)
            audio.noteOff(key:note,channel:0);try await render(14400,measure:false)
        }
        audio.sustain(true,layers:[layer])
        for note in notes {audio.noteOn(key:note,pitch:note,instrument:layer.instrument,layer:0,velocity:1);audio.noteOff(key:note,channel:0)}
        try await render(48000,measure:false);audio.sustain(false,layers:[layer]);try await render(24000,measure:false)
        if let error=loadError{throw failure(error)}
        guard count>0 else{throw failure("No calibration audio was rendered.")}
        return try recommendation(rms:sqrt(energy/Double(count)),peak:peak,targetDB:targetDB)
    }
}
