param([string]$Source='C:/Users/johnw/OneDrive/Documents/ChatGPT/Mouse Frontier 8.10')
$ErrorActionPreference='Stop'
$arcadeRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$arcadeCode=Join-Path $arcadeRoot 'src/arcade_frontier'
$arcadeArt=Join-Path $arcadeRoot 'assets/generated/frontier-arcade'
New-Item -ItemType Directory -Force -Path $arcadeCode,$arcadeArt | Out-Null
$arcadeModules=@('shooting_range','last_stand_shootout','last_stand_tuning','last_stand_scene_data','window_scene','train_ambush','train_ambush_rules','train_ambush_scene','first_person_shooting','first_person_weapon_views','first_person_weapon_manifest','first_person_weapon_actions','first_person_weapon_grips','first_person_weapon_muzzles','mobile_weapon_aim','weapon_sound_profiles','typography','world_view','accessibility')
$arcadeManifest=@()
foreach($arcadeName in $arcadeModules){
    $arcadeSource=Join-Path $Source ('game/'+$arcadeName+'.lua')
    $arcadeText=[IO.File]::ReadAllText($arcadeSource).Replace('require("game.','require("src.arcade_frontier.').Replace('"assets/','"assets/generated/frontier-arcade/assets/').Replace('"sounds/','"assets/generated/frontier-arcade/sounds/')
    # Keep the original solo behavior while exposing shared encounter hooks.
    if ($arcadeName -eq 'last_stand_shootout') {
        $arcadeText=$arcadeText.Replace('data.health=math.max(1,health-damage)',"if state.arcadeHit then state.arcadeHit(damage)`n        else data.health=math.max(1,health-damage) end")
        $arcadeText=$arcadeText.Replace('    FirstPerson.update(state.gun,dt,data,state.quest,width,height)','    if not state.arcadeCoop then FirstPerson.update(state.gun,dt,data,state.quest,width,height) end')
        $arcadeText=$arcadeText.Replace('if FirstPerson.needsSupply(state.gun,data,state.quest) then return nil end','if not state.arcadeCoop and FirstPerson.needsSupply(state.gun,data,state.quest) then return nil end')
    }
    if ($arcadeName -eq 'train_ambush_rules') {
        $arcadeText=$arcadeText.Replace('                                if onEnemyFire then onEnemyFire(vehicle.id,index) end','')
        $arcadeText=$arcadeText.Replace('if state.coverProgress<1 then',"local handled=onEnemyFire and onEnemyFire(vehicle.id,index)`n                                if not handled and state.coverProgress<1 then")
    }
    [IO.File]::WriteAllText((Join-Path $arcadeCode ($arcadeName+'.lua')),$arcadeText,[Text.UTF8Encoding]::new($false))
    $arcadeManifest+=@{source='game/'+$arcadeName+'.lua';sha256=(Get-FileHash -LiteralPath $arcadeSource -Algorithm SHA256).Hash}
}
$arcadeFiles=@()
foreach($arcadeDir in @('assets/sprites/props/shooting-range','assets/sprites/quests/last-stand/runtime','assets/sprites/events/train-ambush')){
    $arcadeFiles+=Get-ChildItem -LiteralPath (Join-Path $Source $arcadeDir) -File | Where-Object Extension -eq '.png'
}
$arcadeFiles+=Get-Item -LiteralPath (Join-Path $Source 'assets/backgrounds/stop-12-industrial-waste.png'),(Join-Path $Source 'assets/fonts/CourierPrime-Regular.ttf'),(Join-Path $Source 'assets/fonts/CourierPrime-Bold.ttf')
foreach($arcadeWeapon in @('frontier-22-lever-rifle','frontier-9mm-service-pistol','sawed-off-shotgun')){
    foreach($arcadeSuffix in @('-hip.png','-sights.png','-actions.png','-ads-fire.png')){
        $arcadeSubdir=if($arcadeSuffix -in @('-actions.png','-ads-fire.png')){'actions/'}else{''}
        $arcadeFiles+=Get-Item -LiteralPath (Join-Path $Source ('assets/sprites/weapons/first-person/'+$arcadeSubdir+$arcadeWeapon+$arcadeSuffix))
    }
}
$arcadeSoundText=[IO.File]::ReadAllText((Join-Path $Source 'game/weapon_sound_profiles.lua'))
foreach($arcadeMatch in [regex]::Matches($arcadeSoundText,'"(sounds/[^"]+)"')){
    $arcadeFiles+=Get-Item -LiteralPath (Join-Path $Source $arcadeMatch.Groups[1].Value)
}
foreach($arcadeFile in ($arcadeFiles | Sort-Object FullName -Unique)){
    $arcadeRelative=$arcadeFile.FullName.Substring($Source.Length+1).Replace('\','/')
    $arcadeDestination=Join-Path $arcadeArt $arcadeRelative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $arcadeDestination) | Out-Null
    Copy-Item -LiteralPath $arcadeFile.FullName -Destination $arcadeDestination
    $arcadeManifest+=@{source=$arcadeRelative;sha256=(Get-FileHash -LiteralPath $arcadeFile.FullName -Algorithm SHA256).Hash}
}
@{sourceProject='Mouse Frontier 8.10';modules=$arcadeModules;adaptation='Requires and asset paths namespaced; campaign services replaced by disposable arcade adapters; Last Stand and Train Attack expose shared damage and update hooks for local and LAN co-op.';files=$arcadeManifest} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $arcadeArt 'import-manifest.json') -Encoding utf8
Write-Output ('Imported '+$arcadeModules.Count+' modules and '+$arcadeFiles.Count+' assets.')
