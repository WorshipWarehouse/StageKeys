import AVFoundation
import AudioToolbox

/// In-process effect unit; no external plug-in installation or discovery.
final class BuiltinEffectUnit: AUAudioUnit {
    static let component=AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:0x736b6678,componentManufacturer:0x53744b79,componentFlags:0,componentFlagsMask:0)
    private static let registration:Void={AUAudioUnit.registerSubclass(BuiltinEffectUnit.self,as:component,name:"StageKeys: Built-in Effects",version:1)}()
    static func make()->AVAudioUnitEffect {_ = registration;return AVAudioUnitEffect(audioComponentDescription:component)}
    private var input:AUAudioUnitBus!
    private var output:AUAudioUnitBus!
    private var inputs:AUAudioUnitBusArray!
    private var outputs:AUAudioUnitBusArray!
    private var scratch:AVAudioPCMBuffer?
    private var left:OpaquePointer?
    private var right:OpaquePointer?
    private struct Setting {var kind=0;var enabled=false;var values:[Float]=[];var tempo:Float=120;var delay:ImportedDelay?}
    private var settings=Array(repeating:Setting(),count:3)
    override init(componentDescription:AudioComponentDescription,options:AudioComponentInstantiationOptions=[]) throws {
        try super.init(componentDescription:componentDescription,options:options)
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        input=try AUAudioUnitBus(format:format);output=try AUAudioUnitBus(format:format)
        inputs=AUAudioUnitBusArray(audioUnit:self,busType:.input,busses:[input]);outputs=AUAudioUnitBusArray(audioUnit:self,busType:.output,busses:[output])
        maximumFramesToRender=4096
    }
    override var inputBusses:AUAudioUnitBusArray {inputs}
    override var outputBusses:AUAudioUnitBusArray {outputs}
    override var canProcessInPlace:Bool {true}
    override func allocateRenderResources() throws {
        guard output.format.sampleRate==input.format.sampleRate,output.format.channelCount==2,input.format.channelCount==2,output.format.commonFormat == .pcmFormatFloat32,!output.format.isInterleaved else {throw NSError(domain:NSOSStatusErrorDomain,code:Int(kAudioUnitErr_FormatNotSupported))}
        try super.allocateRenderResources()
        let capacity=settings.contains{$0.delay != nil} ? 16.0:2.0
        left=sk_create_effects_with_capacity(output.format.sampleRate,capacity);right=sk_create_effects_with_capacity(output.format.sampleRate,capacity)
        guard left != nil,right != nil,let buffer=AVAudioPCMBuffer(pcmFormat:output.format,frameCapacity:maximumFramesToRender) else {releaseDSP();throw NSError(domain:NSOSStatusErrorDomain,code:Int(kAudioUnitErr_FailedInitialization))}
        scratch=buffer
        for slot in settings.indices {apply(slot)}
    }
    private func releaseDSP(){if let left {sk_destroy(left)};if let right {sk_destroy(right)};left=nil;right=nil;scratch=nil}
    override func deallocateRenderResources(){releaseDSP();super.deallocateRenderResources()}
    deinit {releaseDSP()}
    func configure(slot:Int,kind:Int,enabled:Bool,values:[Float],tempo:Float,delay:ImportedDelay?=nil){
        guard (0..<3).contains(slot),(0...17).contains(kind) else{return}
        var clean=AudioEffectCatalog.defaults(for:kind)
        for p in AudioEffectCatalog.descriptors(for:kind) {let value=p.index<values.count ? values[p.index]:p.defaultValue;clean[p.index]=value.isFinite ? max(p.minimum,min(p.maximum,value)):p.defaultValue}
        // Internal engine selector is deliberately separate from visible controls.
        // Keep it across format changes and render-resource reallocation.
        if kind==13 {clean.append(values.count>10 && values[10].isFinite && values[10]>0 ? 1:0)}
        settings[slot]=Setting(kind:kind,enabled:enabled,values:clean,tempo:max(20,min(300,tempo)),delay:delay)
        apply(slot)
    }
    private func apply(_ slot:Int){
        let setting=settings[slot]
        for (side,pointer) in [left,right].enumerated() {
            guard let pointer else{continue}
            sk_effect(pointer,0,Int32(slot),setting.enabled ? Int32(setting.kind):0,1)
            sk_clock(pointer,setting.tempo,0)
            let delay=setting.delay
            let leftSeconds=delay.map{$0.seconds($0.left,synced:$0.leftSynced,tempo:setting.tempo)} ?? 0.001
            let rightSeconds=delay.map{$0.seconds($0.right,synced:$0.rightSynced,tempo:setting.tempo)} ?? 0.001
            let channel=side==0 ? delay?.leftChannel:delay?.rightChannel
            sk_imported_delay_channel(pointer,Int32(slot),channel != nil ? 1:0,(channel?.feedback ?? 0)*(channel?.feedbackPolarity ?? 1),(channel?.crossFeedback ?? 0)*(channel?.crossPolarity ?? 1),channel?.mix ?? 0,Int32(channel?.input ?? (side==0 ? 1:2)))
            sk_imported_delay(pointer,Int32(slot),delay != nil && setting.enabled ? 1:0,leftSeconds,rightSeconds,delay?.pingPong == true ? 1:0,channel?.lowCut ?? delay?.lowCut ?? 20,channel?.highCut ?? delay?.highCut ?? 20000)
            if setting.enabled {for (index,value) in setting.values.enumerated(){sk_effect_parameter(pointer,0,Int32(slot),Int32(index),value)}}
        }
    }
    override func reset(){super.reset();if let left{sk_panic(left)};if let right{sk_panic(right)}}
    override var internalRenderBlock:AUInternalRenderBlock {
        { [weak self] flags,time,frames,bus,data,_,pull in
            guard let self,let pull,let buffer=self.scratch,let left=self.left,let right=self.right,frames<=buffer.frameCapacity,bus==0 else{return kAudioUnitErr_Uninitialized}
            buffer.frameLength=frames
            let inputData=buffer.mutableAudioBufferList
            let status=pull(flags,time,frames,0,inputData)
            guard status==noErr else{return status}
            let input=UnsafeMutableAudioBufferListPointer(inputData),out=UnsafeMutableAudioBufferListPointer(data)
            guard input.count==2,out.count==2,let l=input[0].mData,let r=input[1].mData else{return kAudioUnitErr_FormatNotSupported}
            sk_process_effects_stereo(left,right,l.assumingMemoryBound(to:Float.self),r.assumingMemoryBound(to:Float.self),frames)
            for channel in 0..<2 {
                let bytes=Int(frames)*MemoryLayout<Float>.size
                if out[channel].mData==nil {out[channel].mData=input[channel].mData}
                else if out[channel].mData != input[channel].mData {memcpy(out[channel].mData!,input[channel].mData!,bytes)}
                out[channel].mDataByteSize=UInt32(bytes)
            }
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            return noErr
        }
    }
}
