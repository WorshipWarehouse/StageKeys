import Foundation

/// Settings observed in the user's accessible Sunday Keys demo, never a bundled sound asset.
enum SundayFactoryVoicing {
    static func feltRoom(from source:LibrarySound)->LibrarySound? {
        guard source.name.hasPrefix("SK App Felt Piano"),let sound=source.sound else{return nil}
        var layer=Layer(name:"SK Felt Piano | Room",instrument:-1,gain:0.5);layer.external=sound
        var settings=layer.channelSettings
        settings.samplerGain=pow(10,-3.0/20);settings.voiceCount=32
        func q(_ bandwidth:Double)->Float {Float(1/(2*sinh(bandwidth*log(2)/2)))}
        settings.equalizer=[EQBand(frequency:20),EQBand(frequency:200,gain:-3),EQBand(frequency:197,gain:-2,q:q(0.28)),EQBand(frequency:345,gain:-5.5,q:q(0.3)),EQBand(frequency:1000,gain:0,q:q(0.5)),EQBand(frequency:5417,gain:-6,q:q(0.73)),EQBand(frequency:1734,gain:7.5),EQBand(frequency:9000)]
        settings.eqEnabled=true;settings.compressorEnabled=true;settings.compressorInputGain=0;settings.compressorAttack=0.02;settings.compressorRelease=0.2;settings.ratio=3;settings.threshold = -26;settings.compressorMix=0.68;settings.makeup=3
        layer.channelSettings=settings
        var room=AudioEffect();room.kind=13
        // Same identified open-source reverb family; wrapper mapping remains under verification.
        room.reverbCore="creamcoat"
        room.parameters=[0,18,0.33,776,2884,0,0,1,0.23,1]
        var delay=AudioEffect();delay.kind=3;delay.enabled=false
        var shimmer=AudioEffect();shimmer.kind=10;shimmer.enabled=false
        layer.effects=[delay,room,shimmer]
        var tags=SoundTags(category:"Acoustic Piano & Keys",type:"Felt Piano",timbres:["Warm"],articulations:["Struck"],sourceModel:"Sunday App sampler")
        tags.noteRanges=[LibraryNoteRange.full.rawValue]
        tags.types=["Acoustic Piano","Felt Piano"]
        return LibrarySound(id:source.id+"-room-voicing-v1",name:layer.name,collection:"Sunday App · Voiced",sound:sound,layer:layer,tags:tags,conversionNotes:["EQ, channel compression, sampler level and room effect settings observed in the accessible SK Felt Piano | Room demo. Native sampler state and audio are reused unchanged.","Reverb uses Airwindows CreamCoat with normalized 9% predelay. The complete Sunday Keys wrapper mapping and processed output are not yet verified identical."])
    }
}
