#Requires -Modules Logging

# dfbhd.exe has no command-line server mode. A game hosted from the menus while the game runs with
# /autorestart is saved to autores.bin, and `dfbhd.exe /autorestart` hosts that game again straight
# away. This hook writes the DFBHD_* settings into dfv.cfg (the game's own settings file), then
# builds autores.bin from dfv.cfg plus the game type and map rotation, on every start.
#
# autores.bin layout (v1.5.0.5, little-endian):
#   0x0000  "autorestartV0.0" (15 bytes, no terminator)
#   0x000F  int32 number of missions in the rotation
#   0x0013  0x1334 bytes host session state (current mission file at +0x3A, game type at +0x27C)
#   0x1347  0x538 bytes settings, the in-memory copy of dfv.cfg (offsets in $settings below)
#   0x187F  int32 (0x00A147E8 in every saved file)
#   0x1883  128 mission records of 0x730 bytes: file name at +0x000, title at +0x20F
# The settings saved here override dfv.cfg, so the hook keeps both in step.

$root     = $Env:SERVER_ROOT
$cfgFile  = Join-Path $root 'dfv.cfg'
$autores  = Join-Path $root 'autores.bin'
$latin1   = [System.Text.Encoding]::Latin1

if (-not (Test-Path -Path (Join-Path $root 'dfbhd.exe'))) {
    Write-Log -Level Error "dfbhd.exe not found in $root; skipping server configuration"
    return
}
if (-not (Test-Path -Path $cfgFile)) {
    Write-Log -Level Error "dfv.cfg not found in $root. It ships with the game; copy it from an install. Without it the game shows its first-run video setup and never hosts."
    return
}

# Game types: DFBHD_GAME_TYPE -> mp_gametype value, and the bit a mission sets in the u16 at
# offset 0x8A of its .bms header when it supports that type.
$gameTypes = [ordered]@{
    'dm'    = @{ Id = 0; Bit = 0x0200; Name = 'Deathmatch' }
    'tdm'   = @{ Id = 1; Bit = 0x2000; Name = 'Team Deathmatch' }
    'tkoth' = @{ Id = 3; Bit = 0x4000; Name = 'Team King of the Hill' }
    'koth'  = @{ Id = 4; Bit = 0x0400; Name = 'King of the Hill' }
    'sd'    = @{ Id = 5; Bit = 0x8000; Name = 'Search and Destroy' }
    'ad'    = @{ Id = 6; Bit = 0x0080; Name = 'Attack and Defend' }
    'ctf'   = @{ Id = 7; Bit = 0x1000; Name = 'Capture the Flag' }
    'fb'    = @{ Id = 8; Bit = 0x0800; Name = 'Flagball' }
}
$aliases = @{
    'deathmatch' = 'dm'; 'teamdeathmatch' = 'tdm'; 'teamkingofthehill' = 'tkoth'; 'tkh' = 'tkoth'
    'kingofthehill' = 'koth'; 'kh' = 'koth'; 'searchanddestroy' = 'sd'; 's&d' = 'sd'
    'attackanddefend' = 'ad'; 'a&d' = 'ad'; 'capturetheflag' = 'ctf'; 'flagball' = 'fb'
}

$typeKey = ($Env:DFBHD_GAME_TYPE ?? '').ToLowerInvariant() -replace '[\s_-]', ''
if ($aliases.ContainsKey($typeKey)) { $typeKey = $aliases[$typeKey] }
if (-not $gameTypes.Contains($typeKey)) {
    Write-Log -Level Warning "Unknown DFBHD_GAME_TYPE '$($Env:DFBHD_GAME_TYPE)' (use $($gameTypes.Keys -join ', ')); using tdm"
    $typeKey = 'tdm'
}
$gameType = $gameTypes[$typeKey]

# ---------------------------------------------------------------------------------------------
# dfv.cfg
# ---------------------------------------------------------------------------------------------

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in [System.IO.File]::ReadAllText($cfgFile, $latin1) -split "`r?`n") { $lines.Add($line) }
if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }

function Get-CfgValue([string] $Key) {
    foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") { return $Matches[1] }
    }
    return $null
}

function Set-CfgValue([string] $Key, [string] $Value) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^(\s*$([regex]::Escape($Key))\s*=\s*)") {
            $lines[$i] = $Matches[1] + $Value
            return
        }
    }
    $lines.Add(('{0,-16} = {1}' -f $Key, $Value))
}

function ConvertTo-CfgString([string] $Value, [int] $MaxLength) {
    $Value = $Value.Replace('"', "'")
    if ($Value.Length -gt $MaxLength) {
        Write-Log -Level Warning "'$Value' is longer than $MaxLength characters; truncating"
        $Value = $Value.Substring(0, $MaxLength)
    }
    return '"' + $Value + '"'
}

# Display: the game creates a fullscreen Direct3D device at 640x480 for its menus, and the only
# mode the virtual display has is its own size. hw3d_name/hw3d_guid are what Wine's Direct3D
# reports; any other card makes the game run its interactive first-run video test.
$forced = [ordered]@{
    windowed          = '0'
    hw3d_deviceno     = '0'
    hw3d_name         = '"NVIDIA GeForce GTX 470"'
    hw3d_guid         = '"AEB2CDD4-6E41-43EA-941C8361CC760781"'
    hw3d_matchz       = '1'
    hw3d_res512x384   = '0'
    hw3d_res640x480   = '0'
    hw3d_res800x600   = '0'
    hw3d_res1024x768  = '1'
    hw3d_res1280x1024 = '0'
    hw3d_res1600x1200 = '1'
    hw3d_res1920x1440 = '0'
    hw3d_res2048x1536 = '0'
    game_res          = '4'
    antialias_mode    = '0'
    mp_eula_accepted  = '1'
    join_password     = '""'  # the password this copy last typed when joining someone else
    dedicated         = '1'   # "Serve" (dedicated) instead of "Serve and Play"
    mp_service        = '2'   # LAN IP; NovaWorld is gone
}
foreach ($key in $forced.Keys) { Set-CfgValue $key $forced[$key] }

Set-CfgValue 'mp_gametype' $gameType.Id
if ($Env:DFBHD_PORT)         { Set-CfgValue 'mp_ServerGamePort' $Env:DFBHD_PORT }
if ($Env:DFBHD_SERVER_NAME)  { Set-CfgValue 'game_name' (ConvertTo-CfgString $Env:DFBHD_SERVER_NAME 31) }
if ($Env:DFBHD_MAX_PLAYERS)  { Set-CfgValue 'maxplayers' $Env:DFBHD_MAX_PLAYERS }
if ($Env:DFBHD_TIME_LIMIT)   { Set-CfgValue 'time_limit' $Env:DFBHD_TIME_LIMIT }
if ($Env:DFBHD_SCORE_LIMIT)  { Set-CfgValue 'max_kills' $Env:DFBHD_SCORE_LIMIT }
if ($Env:DFBHD_RESPAWN_TIME) { Set-CfgValue 'timeout' $Env:DFBHD_RESPAWN_TIME }
# Always written, so clearing a variable clears the setting. host_password is the server's join
# password; join_password is only what this copy of the game last typed when joining.
Set-CfgValue 'servermsg' (ConvertTo-CfgString ($Env:DFBHD_MESSAGE ?? '') 127)
Set-CfgValue 'host_password' (ConvertTo-CfgString ($Env:DFBHD_PASSWORD ?? '') 16)

# DFBHD_CONFIG: any other dfv.cfg keys, "key=value;key=value". Strings need their quotes.
if ($Env:DFBHD_CONFIG) {
    foreach ($pair in $Env:DFBHD_CONFIG -split ';') {
        if (-not $pair.Trim()) { continue }
        $key, $value = $pair -split '=', 2
        if ($null -eq $value) {
            Write-Log -Level Warning "Ignoring '$pair' in DFBHD_CONFIG (expected key=value)"
            continue
        }
        Set-CfgValue $key.Trim() $value.Trim()
    }
}

[System.IO.File]::WriteAllText($cfgFile, ($lines -join "`r`n") + "`r`n", $latin1)
chown "$($Env:UID):$($Env:GID)" $cfgFile

# ---------------------------------------------------------------------------------------------
# Missions
# ---------------------------------------------------------------------------------------------

# Every .bms the game can load: loose files in the game folder, then the .pff archives in the
# order the game searches them. Returns file name, title and supported game type bits.
function Get-Missions {
    $missions = [ordered]@{}

    function Add-Mission([string] $Name, [byte[]] $Header) {
        if ($Header.Length -lt 0x8C -or $latin1.GetString($Header, 0, 3) -ne 'BMS') { return }
        $key = [System.IO.Path]::GetFileNameWithoutExtension($Name).ToUpperInvariant()
        if ($missions.Contains($key)) { return }
        $title = $latin1.GetString($Header, 4, 32).Split([char]0)[0]
        $missions[$key] = [pscustomobject]@{
            File  = $Name.ToUpperInvariant()
            Title = $title
            Types = [System.BitConverter]::ToUInt16($Header, 0x8A)
        }
    }

    foreach ($file in Get-ChildItem -Path $root -Filter '*.bms' -File -ErrorAction SilentlyContinue) {
        $stream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $header = [byte[]]::new(0x90)
            $read = $stream.Read($header, 0, $header.Length)
            Add-Mission $file.Name $header[0..($read - 1)]
        } finally {
            $stream.Dispose()
        }
    }

    foreach ($pffName in 'exp3.pff', 'exp2.pff', 'exp1.pff', 'localres.pff', 'resource.pff') {
        $pff = Get-ChildItem -Path $root -File | Where-Object { $_.Name -ieq $pffName } | Select-Object -First 1
        if (-not $pff) { continue }
        try {
            $stream = [System.IO.File]::OpenRead($pff.FullName)
            try {
                $reader = [System.IO.BinaryReader]::new($stream)
                # Header: size, magic ("PFF3", or 01 00 'F4'), entry count, entry size, directory offset
                $null = $reader.ReadUInt32(); $null = $reader.ReadUInt32()
                $count = $reader.ReadUInt32(); $entrySize = $reader.ReadUInt32(); $dirOffset = $reader.ReadUInt32()
                $stream.Position = $dirOffset
                $directory = $reader.ReadBytes([int]($count * $entrySize))
                for ($i = 0; $i -lt $count; $i++) {
                    # Entry: deleted flag, data offset, size, timestamp, name[16]
                    $e = $i * $entrySize
                    if ([System.BitConverter]::ToUInt32($directory, $e) -ne 0) { continue }
                    $name = $latin1.GetString($directory, $e + 16, 16).Split([char]0)[0]
                    if (-not $name.EndsWith('.bms', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $stream.Position = [System.BitConverter]::ToUInt32($directory, $e + 4)
                    Add-Mission $name $reader.ReadBytes(0x90)
                }
            } finally {
                $stream.Dispose()
            }
        } catch {
            Write-Log -Level Warning "Could not read $($pff.Name): $_"
        }
    }

    return $missions
}

$missions = Get-Missions
$candidates = @($missions.Values | Where-Object { $_.Types -band $gameType.Bit })
if ($candidates.Count -eq 0) {
    Write-Log -Level Error "Found no $($gameType.Name) missions in $root/*.pff; not writing autores.bin"
    return
}

$rotation = [System.Collections.Generic.List[object]]::new()
if ($Env:DFBHD_MAPS) {
    foreach ($item in $Env:DFBHD_MAPS -split '[,;\s]+') {
        if (-not $item) { continue }
        $key = ($item -replace '(?i)\.bms$', '').ToUpperInvariant()
        if (-not $missions.Contains($key)) {
            Write-Log -Level Warning "Mission '$item' not found; dropping it from the rotation"
        } elseif (-not ($missions[$key].Types -band $gameType.Bit)) {
            Write-Log -Level Warning "Mission '$item' doesn't support $($gameType.Name); dropping it from the rotation"
        } else {
            $rotation.Add($missions[$key])
        }
    }
    if ($rotation.Count -eq 0) { Write-Log -Level Warning "DFBHD_MAPS has no usable missions; using every $($gameType.Name) mission" }
}
if ($rotation.Count -eq 0) { $candidates | ForEach-Object { $rotation.Add($_) } }
if ($rotation.Count -gt 128) {
    Write-Log -Level Warning "The rotation holds at most 128 missions; using the first 128"
    $rotation = $rotation.GetRange(0, 128)
}

# ---------------------------------------------------------------------------------------------
# autores.bin
# ---------------------------------------------------------------------------------------------

# dfv.cfg key -> offset in the settings block and type (I = int32, S<n> = n-byte string field)
$settings = @{
    player_index = @(0x000, 'I'); play_exit_credits = @(0x008, 'I'); version = @(0x00C, 'I')
    windowed = @(0x010, 'I'); hw3d_name = @(0x018, 'S32'); hw3d_guid = @(0x038, 'S36')
    hw3d_matchz = @(0x060, 'I'); game_res = @(0x064, 'I'); bit_depth = @(0x068, 'I')
    disable_vshaders = @(0x070, 'I'); disable_pshaders = @(0x074, 'I'); no_anim = @(0x07C, 'I')
    window_size = @(0x088, 'I'); terrain_detail = @(0x114, 'I'); object_detail = @(0x118, 'I')
    texture_res = @(0x11C, 'I'); water_quality = @(0x120, 'I'); shadow_quality = @(0x124, 'I')
    particle_density = @(0x128, 'I'); antialias_mode = @(0x12C, 'I'); foliage = @(0x130, 'I')
    rotorwash = @(0x134, 'I'); grouping = @(0x138, 'I'); NoBlood = @(0x164, 'I')
    NoSmoke = @(0x168, 'I'); NoCasings = @(0x16C, 'I'); AltLock = @(0x170, 'I')
    AltLockType = @(0x174, 'I'); crosshairs = @(0x178, 'I'); showgun = @(0x17C, 'I')
    picinpic = @(0x180, 'I'); preempt_pff = @(0x184, 'I'); map_infrared = @(0x1A0, 'I')
    map_iff = @(0x1A4, 'I'); map_AWAC = @(0x1A8, 'I'); windows_volume = @(0x1BC, 'I')
    music_volume = @(0x1C0, 'I'); SFXLevel = @(0x1C4, 'I'); DialogueLevel = @(0x1C8, 'I')
    rotor_volume = @(0x1CC, 'I'); audio_channels = @(0x1D0, 'I'); mp_eula_accepted = @(0x1D4, 'I')
    mpattrib = @(0x1D8, 'I'); mp_gameport = @(0x1DC, 'I'); mp_vonport = @(0x1E0, 'I')
    mp_usealtnwport = @(0x1E4, 'I'); host_password = @(0x1E8, 'S17'); join_password = @(0x1F9, 'S17')
    team_password = @(0x20A, 'S17'); red_password = @(0x21B, 'S17'); blue_password = @(0x22C, 'S17')
    yellow_password = @(0x23D, 'S17'); violet_password = @(0x24E, 'S17'); game_name = @(0x25F, 'S32')
    country = @(0x27F, 'S4'); phone_number = @(0x283, 'S32'); internet_address = @(0x2A3, 'S33')
    mp_gametype = @(0x2C4, 'I'); maxplayers = @(0x2C8, 'I'); dedicated = @(0x2CC, 'I')
    com_port = @(0x2D0, 'I'); baud_rate = @(0x2D4, 'I'); max_team_lives = @(0x2D8, 'I')
    max_kills = @(0x2DC, 'I'); startdelay = @(0x2E0, 'I'); destroybuild = @(0x2E4, 'I')
    deathmes = @(0x2E8, 'I'); flagreturntime = @(0x2EC, 'I'); team_req = @(0x2F0, 'I')
    replay = @(0x2F4, 'I'); time_limit = @(0x2F8, 'I'); koth_limit = @(0x2FC, 'I')
    timeout = @(0x300, 'I'); mp_service = @(0x304, 'I'); mp_difficulty = @(0x308, 'I')
    mp_numteams = @(0x30C, 'I'); mp_NoCharAbilities = @(0x310, 'I'); mp_NoWeaponRecoil = @(0x314, 'I')
    mp_NoScopeDrift = @(0x318, 'I'); mp_NoCrossHairSpread = @(0x31C, 'I'); mp_gpsicons = @(0x320, 'I')
    mp_wind = @(0x324, 'I'); mp_DroppedWeaponDisappear = @(0x328, 'I'); mp_NoDropWeapons = @(0x32C, 'I')
    mp_NoRespawnWithPrimary = @(0x330, 'I'); showtags = @(0x334, 'I'); contest = @(0x338, 'I')
    level_restricted = @(0x33C, 'I'); min_level = @(0x340, 'I'); max_level = @(0x344, 'I')
    ping = @(0x34C, 'I'); sendplayerlist = @(0x350, 'I'); teamchange_time = @(0x354, 'I')
    msg = @(0x358, 'S24'); hud_color_index = @(0x370, 'I'); hud_detail = @(0x374, 'I')
    whichbrowser = @(0x378, 'I'); turbo = @(0x37C, 'I'); mp_verbose = @(0x380, 'I')
    crosshairs_color = @(0x384, 'I'); mp_ServerGamePort = @(0x388, 'I'); mp_ClientGamePort = @(0x38C, 'I')
    allowcustomskins = @(0x390, 'I'); hostrequiresnovaworldlogin = @(0x394, 'I'); oneshotonekill = @(0x398, 'I')
    fatbullets = @(0x39C, 'I'); nwisptype = @(0x3A4, 'I'); lanmode = @(0x3A8, 'I')
    minping = @(0x3AC, 'I'); dominpingcheck = @(0x3B0, 'I'); maxping = @(0x3B4, 'I')
    domaxpingcheck = @(0x3B8, 'I'); dirtyupstream = @(0x3BC, 'I'); dirtyupstreampost = @(0x3C0, 'I')
    servermsg = @(0x3C4, 'S128'); numallowablefriendlykills = @(0x444, 'I')
}
$resolutions = '512x384', '640x480', '800x600', '1024x768', '1280x1024', '1600x1200', '1920x1440', '2048x1536'

# Settings-block fields that aren't in dfv.cfg (controls, unlocks, gamma), as the game saves them
$settingsDefaults = @{
    0x004 = 1; 0x080 = 0x3F4CCCCD; 0x084 = 6; 0x08C = 1; 0x090 = 1; 0x094 = 1; 0x098 = 0x4000
    0x09C = 0x4000; 0x0A0 = 0x4000; 0x0A4 = 8; 0x0A8 = 1; 0x0B0 = -1; 0x0B4 = 1; 0x0B8 = 1
    0x0BC = 1; 0x0C4 = 1; 0x0C8 = 1; 0x0CC = 1; 0x0D0 = 1; 0x0D4 = 1; 0x0D8 = 1; 0x0DC = 1
    0x0E0 = 1; 0x0E8 = 1; 0x0EC = 18; 0x0F0 = 1; 0x0F4 = 1; 0x104 = 1; 0x10C = 1; 0x110 = 1
    0x13C = 3; 0x140 = 2; 0x148 = 3; 0x14C = 3; 0x150 = 2; 0x154 = 4; 0x158 = 1; 0x15C = 1
    0x190 = 0x20000
}
for ($o = 0x448; $o -lt 0x538; $o += 4) { $settingsDefaults[$o] = 1 }

# Session-state fields, as the game saves them for a dedicated LAN host. The loader only re-hosts
# when +0x260 and +0x268 are set and +0x26C is clear.
$sessionDefaults = @{ 0x1B4 = 1; 0x1E4 = 1; 0x1E8 = 1; 0x228 = 1; 0x260 = 1; 0x264 = 2; 0x268 = 1; 0x288 = 5 }

$session  = [byte[]]::new(0x1334)
$block    = [byte[]]::new(0x538)
$records  = [byte[]]::new(128 * 0x730)

function Write-Int([byte[]] $Buffer, [int] $Offset, [long] $Value) {
    [System.BitConverter]::GetBytes([int]$Value).CopyTo($Buffer, $Offset)
}
function Write-String([byte[]] $Buffer, [int] $Offset, [int] $Size, [string] $Value) {
    [array]::Clear($Buffer, $Offset, $Size)
    $bytes = $latin1.GetBytes($Value)
    [array]::Copy($bytes, 0, $Buffer, $Offset, [Math]::Min($bytes.Length, $Size - 1))
}

foreach ($o in $sessionDefaults.Keys) { Write-Int $session $o $sessionDefaults[$o] }
foreach ($o in $settingsDefaults.Keys) { Write-Int $block $o $settingsDefaults[$o] }

$resMask = 0
foreach ($line in $lines) {
    if ($line -notmatch '^\s*([A-Za-z_0-9]+)\s*=\s*(.*?)\s*$') { continue }
    $key, $value = $Matches[1], $Matches[2]
    if ($key -like 'hw3d_res*') {
        $index = [array]::IndexOf($resolutions, $key.Substring(8))
        if ($index -ge 0 -and $value -match '^-?\d+$' -and [int]$value) { $resMask = $resMask -bor (1 -shl $index) }
        continue
    }
    if (-not $settings.ContainsKey($key)) { continue }
    $offset, $type = $settings[$key]
    if ($type -eq 'I') {
        if ($value -match '^-?\d+$') { Write-Int $block $offset ([long]$value) }
        else { Write-Log -Level Warning "dfv.cfg: $key = $value isn't a number; ignoring it" }
    } else {
        Write-String $block $offset ([int]$type.Substring(1)) $value.Trim('"')
    }
}
Write-Int $block 0x05C $resMask

for ($i = 0; $i -lt $rotation.Count; $i++) {
    Write-String $records ($i * 0x730) 0x20F $rotation[$i].File
    Write-String $records ($i * 0x730 + 0x20F) 0x100 $rotation[$i].Title
}

$maxPlayers = Get-CfgValue 'maxplayers'
Write-String $session 0x3A 0x20 $rotation[0].File
Write-Int $session 0x27C $gameType.Id
Write-Int $session 0x270 ($(if ($maxPlayers -match '^\d+$') { [int]$maxPlayers } else { 50 }) + 1)

$out = [System.IO.MemoryStream]::new()
$out.Write($latin1.GetBytes('autorestartV0.0'), 0, 15)
$out.Write([System.BitConverter]::GetBytes([int]$rotation.Count), 0, 4)
$out.Write($session, 0, $session.Length)
$out.Write($block, 0, $block.Length)
$out.Write([System.BitConverter]::GetBytes([int]0x00A147E8), 0, 4)
$out.Write($records, 0, $records.Length)
[System.IO.File]::WriteAllBytes($autores, $out.ToArray())
chown "$($Env:UID):$($Env:GID)" $autores

Write-Log "$($gameType.Name) on port $(Get-CfgValue 'mp_ServerGamePort'), $($rotation.Count) mission(s): $(($rotation | ForEach-Object { $_.File -replace '(?i)\.bms$', '' }) -join ', ')"
