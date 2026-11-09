-- Road characters share a world-space stature with the rider in bike_art.
-- Character strips normalize their visible body to 256 px; apartment/player
-- drawScale belongs to the indoor camera and must not determine road stature.
local Scale={BODY_HEIGHT=80}

function Scale.base(zoom,referenceHeight)
    return Scale.BODY_HEIGHT*(zoom or 1)/(referenceHeight or
        require('src.config').characterRendering.referenceHeight)
end

function Scale.sprite(zoom,normalization)
    return Scale.base(zoom)*(normalization or 1)
end

function Scale.fallback(zoom,helmet)
    -- Procedural fallback is authored from sole to helmet (64 px), or ears
    -- (77 px). Keep it at the same stature while production strips load.
    return Scale.BODY_HEIGHT*(zoom or 1)/(helmet and 64 or 77)
end

return Scale
