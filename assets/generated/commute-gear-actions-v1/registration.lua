-- Runtime registration for the visually reviewed southeast rabbit gear strips.
return {
    status = "runtime_approved",
    character = "rabbit-worker",
    direction = "southeast",
    referenceHeight = 256,
    frameSize = 256,
    anchor = {128, 238},
    actions = {
        suit_on = {
            path = "assets/generated/commute-gear-actions-v1/suit_on_southeast.png",
            maskPath = "assets/generated/commute-gear-actions-v1/suit_on_southeast_mask.png",
            duration = 1.2,
            frameCount = 4,
            normalizationHeight = 215.0,
        },
        zip_up = {
            path = "assets/generated/commute-gear-actions-v1/zip_up_southeast.png",
            maskPath = "assets/generated/commute-gear-actions-v1/zip_up_southeast_mask.png",
            duration = 0.8,
            frameCount = 4,
            normalizationHeight = 218.5,
        },
        boots_gloves = {
            path = "assets/generated/commute-gear-actions-v1/boots_gloves_southeast.png",
            maskPath = "assets/generated/commute-gear-actions-v1/boots_gloves_southeast_mask.png",
            duration = 0.7,
            frameCount = 4,
            normalizationHeight = 218.0,
        },
        helmet_on = {
            path = "assets/generated/commute-gear-actions-v1/helmet_on_southeast.png",
            maskPath = "assets/generated/commute-gear-actions-v1/helmet_on_southeast_mask.png",
            duration = 1.0,
            frameCount = 4,
            normalizationHeight = 213.5,
        },
    },
}
