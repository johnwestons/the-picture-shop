-- Authored southeast action strips for the helmeted motorcycle rider.
return {status='runtime_approved',character='rabbit-worker',
    direction='southeast',referenceHeight=256,frameSize=256,anchor={128,224},
    actions={
        mount={path='assets/generated/commute-ride-actions-v1/mount-southeast.png',maskPath='assets/generated/commute-ride-actions-v1/mount-southeast-mask.png',
            duration=0.8,frameCount=6,
            frameSize=256,anchor={128,224},
            normalizationHeight=228,},
        dismount={path='assets/generated/commute-ride-actions-v1/dismount-southeast.png',maskPath='assets/generated/commute-ride-actions-v1/dismount-southeast-mask.png',
            duration=1.1,frameCount=6,
            frameSize=256,anchor={128,224},
            normalizationHeight=200,},
        crash={path='assets/generated/commute-ride-actions-v1/crash-southeast.png',maskPath='assets/generated/commute-ride-actions-v1/crash-southeast-mask.png',
            duration=1.35,frameCount=8,
            frameSize=256,anchor={128,232},
            normalizationHeight=214,},
    },
}
