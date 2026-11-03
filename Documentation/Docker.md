---
sidebar_label: Docker
---

# Delta Force: Black Hawk Down Docker Container

This Docker container runs a Delta Force: Black Hawk Down – Team Sabre dedicated server. It is built on the WINE image and runs the game itself, `dfbhd.exe`, as a dedicated host on a virtual display. The container doesn't download the game, so you provide a v1.5.0.5 install.

## Quick Start

```yaml
services:
  dfbhd:
    image: lancommander/deltaforceblackhawkdown:latest
    container_name: dfbhd

    ports:
      - 17479:17479/udp

    volumes:
      - "/data/Servers/Delta Force Black Hawk Down/TDM:/config"

    environment:
      DFBHD_SERVER_NAME: "My Black Hawk Down Server"
      DFBHD_GAME_TYPE: "tdm"
      DFBHD_MAPS: "TDMR_01A TDMR_02A TDMR_03A TDMM_01A"
      DFBHD_TIME_LIMIT: "20"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Before the first start, copy a v1.5.0.5 install (the folder with `dfbhd.exe`, `dfv.cfg` and the `.pff` files) into `Server/`, or set `DFBHD_ARCHIVE_URL` to a zip of it.

## How It Starts

The game has no command-line hosting. When you host from the menus while the game runs with `/autorestart`, it saves the session to `autores.bin`, and `dfbhd.exe /autorestart` hosts that saved session again without showing the menus. The image writes that file itself:

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallDeltaForce.ps1` checks for `Server/dfbhd.exe`. If it's missing and `DFBHD_ARCHIVE_URL` is set, the hook downloads the zip and moves the shallowest folder holding `dfbhd.exe` and `resource.pff` into `Server/`. It leaves out the PDF manuals, fixes the file modes and remounts the overlay.
3. `PostInitialization/30-ConfigureDeltaForce.ps1`:
   - writes the `DFBHD_*` settings, `DFBHD_CONFIG` and the display/dedicated settings below into `dfv.cfg`,
   - reads the missions (`*.bms`) from the game folder and from `EXP1.pff`, `localres.pff` and `resource.pff`, and keeps the ones that support the game type,
   - builds `autores.bin` from `dfv.cfg`, the game type and the rotation.
4. `START_EXE` (`/usr/local/bin/dfbhd-server`) runs `dfbhd.exe /autorestart [START_ARGS]` from the server folder under Wine and Xvfb. The game prints nothing to a console, so the launcher follows `ghw.txt` (its graphics and mission log, rewritten on every start) into `docker logs`.

A healthy start ends with:

```
[LANCommander] Team Deathmatch on port 17479, 4 mission(s): TDMR_01A, TDMR_02A, TDMR_03A, TDMM_01A
Starting: dfbhd.exe /autorestart
...
CreateDevice:  device:0   640x480  Z  Fullscreen  c32_d32  aa1
...
Sniper_Start()
Mission:"TDMR_01A.BMS" - "??TDMR_01A??" - "TDMR_01A.BMS" - ""
```

Each map change adds another `Mission:` line.

### Settings the hook always writes

| `dfv.cfg` key | Value | Why |
|---------------|-------|-----|
| `dedicated` | `1` | "Serve" (dedicated) instead of "Serve and Play" |
| `mp_service` | `2` | LAN IP. NovaWorld, the old online service, is gone |
| `mp_eula_accepted` | `1` | Skips the multiplayer EULA |
| `hw3d_name`, `hw3d_guid` | Wine's Direct3D adapter | Any other card makes the game run its interactive first-run video test |
| `windowed`, `game_res`, `hw3d_res*`, `hw3d_matchz`, `antialias_mode` | fullscreen, 640x480-compatible | The game creates a fullscreen 640x480 Direct3D device even as a dedicated server, and the virtual display has one mode |
| `join_password` | empty | It holds the password this copy last typed when joining someone else |

## Configuration Options

### Ports

- **17479/udp**: Game and LAN browser replies (`DFBHD_PORT`). Clients search the LAN by broadcasting to 17479, so change it only for internet-style direct connects.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table and the mission IDs per game type.

### dfv.cfg

`dfv.cfg` is the game's own settings file, and the server's settings come from it. The hook edits it in place (in `Overlay/`), so settings you change there yourself are kept, except those the `DFBHD_*` variables or the table above set. `DFBHD_CONFIG` sets any key on every start. Other host settings (meanings going by the key names and the host screen; only the `DFBHD_*` ones are tested):

| Key | Meaning |
|-----|---------|
| `replay` | What happens after the last mission: `2` cycles the rotation (default) |
| `mp_numteams` | Number of teams in team games |
| `max_team_lives` | Team lives (attack and defend, search and destroy) |
| `koth_limit` | King of the hill hold time in minutes |
| `flagreturntime` | Seconds before a dropped flag returns |
| `startdelay` | Delay before the mission starts |
| `team_req` | Minimum players per team before the game starts |
| `numallowablefriendlykills` | Team kills before a player is kicked |
| `oneshotonekill`, `fatbullets` | Damage options |
| `allowcustomskins` | Allow custom player skins |
| `mp_NoCharAbilities`, `mp_NoWeaponRecoil`, `mp_NoScopeDrift`, `mp_NoCrossHairSpread`, `mp_NoDropWeapons`, `mp_NoRespawnWithPrimary`, `mp_DroppedWeaponDisappear`, `mp_gpsicons`, `mp_wind` | Gameplay switches |
| `red_password`, `blue_password`, `yellow_password`, `violet_password` | Team passwords |
| `minping`, `dominpingcheck`, `maxping`, `domaxpingcheck` | Ping limits |
| `map_infrared`, `map_iff`, `map_AWAC` | Map display options |

### autores.bin

`autores.bin` is regenerated on every start, so edits to it don't survive. For v1.5.0.5 it holds (little-endian):

| Offset | Size | Contents |
|--------|------|----------|
| `0x0000` | 15 | `autorestartV0.0` |
| `0x000F` | 4 | Number of missions in the rotation |
| `0x0013` | `0x1334` | Session state: current mission file at `+0x3A`, game type at `+0x27C` (`0` DM, `1` TDM, `3` TKOTH, `4` KOTH, `5` S&D, `6` A&D, `7` CTF, `8` flagball). The game only re-hosts when `+0x260` and `+0x268` are set and `+0x26C` is clear |
| `0x1347` | `0x538` | The in-memory copy of `dfv.cfg`. These values win over `dfv.cfg` |
| `0x187F` | 4 | `0x00A147E8` in every saved file |
| `0x1883` | 128 × `0x730` | Mission records: file name at `+0x000`, title at `+0x20F` |

A mission's supported game types are the bits of the 16-bit value at offset `0x8A` of its `.bms` file: `0x0080` A&D, `0x0200` DM, `0x0400` KOTH, `0x0800` flagball, `0x1000` CTF, `0x2000` TDM, `0x4000` TKOTH, `0x8000` S&D.

### Custom Missions

Untested. The configure hook also accepts loose `.bms` files in the game folder (`Overlay/`) in `DFBHD_MAPS`, but the game may only read loose files when started with `/d` (`START_ARGS`), and clients need the same files.

### Banning Players

The game keeps bans in `banlist.txt` (`BAN "<pcid>" "<name>"`), loaded at start. Edit it in `Overlay/` and restart.

### Hooks

| Hook | When |
|------|------|
| `PreInstallDeltaForce` / `PostInstallDeltaForce` | Around the install check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **`dfbhd.exe not found` and the container exits**: copy an install into `Server/` or set `DFBHD_ARCHIVE_URL`.
- **`dfv.cfg not found`**: the file ships with the game. Without it, the game runs its first-run video test and waits for clicks.
- **`dfbhd.exe crashed:` followed by an access violation, over and over**: the Direct3D device couldn't be created. Keep `WINE_XVFB_SCREEN=640x480x24`, and don't override the display keys in `DFBHD_CONFIG`. `ghw.txt` shows `Failed to initialize... (8876086A)` for each mode it tried.
- **The game sits at its menus instead of hosting**: `autores.bin` is missing or from another game version. Check the configure hook's log lines.
- **`Mission '...' doesn't support ...`**: the mission is for another game type. See the lists in the README.
- **Not in the in-game server list**: LAN discovery is a broadcast to UDP 17479, so the container must be on the LAN itself (macvlan/ipvlan, or `network_mode: host`) and use port 17479.
- **`XDG_RUNTIME_DIR (/tmp) is not owned by us` and ALSA errors in the log**: harmless. The container has no sound device.
