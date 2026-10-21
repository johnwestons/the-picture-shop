return {audio=function(data)
    local sound=data.arcadeSound
    if sound then return {sfxVolume=(sound.muted or sound.paused) and 0 or sound.masterVolume*sound.sfxVolume} end
    return data.arcadeAudio or {sfxVolume=.45}
end}
