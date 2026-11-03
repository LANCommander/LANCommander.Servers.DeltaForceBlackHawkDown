# Delta Force: Black Hawk Down Server (Docker)

This repository provides a Dockerized **Delta Force: Black Hawk Down** (with the **Team Sabre** expansion) dedicated server. The game has no separate server program: `dfbhd.exe` hosts dedicated games itself. It is Windows-only, so the image runs it under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Installs the game from a zip on first start (`DFBHD_ARCHIVE_URL`), or uses an install you copy in
- Hosts without touching the menus: the image generates the game's own auto-restart file (`autores.bin`) and starts `dfbhd.exe /autorestart`
- Game type, map rotation, server name, message, password, player and time limits are environment variables; any other `dfv.cfg` setting can be set too
- Reads the mission list from the game's `.pff` archives and drops rotation entries that don't exist or don't support the game type
- Restarts the container when the game crashes instead of hanging on its crash dialog
- The game runs on a 640x480 virtual display (Xvfb)
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  dfbhd:
    image: lancommander/deltaforceblackhawkdown:latest
    container_name: dfbhd

    ports:
      - "17479:17479/udp"

    volumes:
      - ./config:/config

    environment:
      DFBHD_SERVER_NAME: "My Black Hawk Down Server"
      DFBHD_GAME_TYPE: "tdm"
      DFBHD_MAPS: "TDMR_01A TDMR_02A TDMR_03A TDMM_01A"
      DFBHD_MAX_PLAYERS: "32"
      DFBHD_TIME_LIMIT: "20"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

---

## Game Files

The game isn't freely downloadable, so the image doesn't include it. You need a Windows **Delta Force: Black Hawk Down – Team Sabre v1.5.0.5** install, i.e. the folder holding `dfbhd.exe`, `dfv.cfg`, `resource.pff`, `localres.pff` and `EXP1.pff`. Either:

- copy it to `config/Server/`, **or**
- set `DFBHD_ARCHIVE_URL` to a zip of it (a `file://` URL works for a zip mounted into the container).

On first start, if `Server/dfbhd.exe` doesn't exist, the install hook downloads and unpacks the zip into `Server/`, leaving out the PDF manuals (about 1.3 GB result).

The `autores.bin` format the image writes is specific to v1.5.0.5. Clients must run the same version.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Game install (dfbhd.exe, dfv.cfg, *.pff ...)
    ├── Overlay/           # Your files, layered on top of Server/ (and what the game writes:
    │                      # dfv.cfg, autores.bin, ghw.txt, dfvplr.sav, banlist.txt)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
Empty optional settings leave the value in `dfv.cfg` alone.

| Variable | Description | Default |
|----------|-------------|---------|
| `DFBHD_ARCHIVE_URL` | URL of a zip of the game folder, used if `Server/dfbhd.exe` is missing | |
| `DFBHD_GAME_TYPE` | `dm` (deathmatch), `tdm` (team deathmatch), `tkoth` (team king of the hill), `koth` (king of the hill), `sd` (search and destroy), `ad` (attack and defend), `ctf` (capture the flag) or `fb` (flagball) | `tdm` |
| `DFBHD_MAPS` | Mission rotation: mission IDs separated by spaces or commas (see below). Empty = every mission for the game type | |
| `DFBHD_PORT` | Game port (`mp_ServerGamePort`) | `17479` |
| `DFBHD_SERVER_NAME` | Game name in the server list (`game_name`, up to 31 characters) | `Delta Force Server` |
| `DFBHD_MESSAGE` | Message shown to players while the mission loads (`servermsg`, up to 127 characters) | |
| `DFBHD_MAX_PLAYERS` | `maxplayers`, up to 50 | `32` |
| `DFBHD_PASSWORD` | Join password (`host_password`, up to 16 characters) | |
| `DFBHD_TIME_LIMIT` | `time_limit`, in minutes | |
| `DFBHD_SCORE_LIMIT` | Kill/score limit (`max_kills`) | |
| `DFBHD_RESPAWN_TIME` | Respawn time in seconds (`timeout`) | |
| `DFBHD_CONFIG` | Any other `dfv.cfg` settings, `key=value` pairs separated by `;`. Strings need their quotes, e.g. `mp_numteams=2;fatbullets=0;red_password="red"` | |
| `WINE_XVFB` | Run on a virtual display. The game can't start without one | `true` |
| `WINE_XVFB_SCREEN` | Virtual display size. Must stay 640x480, the only mode the game's menus can use | `640x480x24` |
| `START_EXE` | Launcher | `/usr/local/bin/dfbhd-server` |
| `START_ARGS` | Added to the `dfbhd.exe /autorestart` command line | |

### Missions

`DFBHD_MAPS` takes mission file names without `.bms` (any case). The mission's name in the game is in the server list and briefing. The stock v1.5.0.5 missions per game type (`R`/`TS` = Team Sabre):

- `dm`: `DMR_01A`, `DMR_02A`, `DMR_03A`, `DMR_04A`, `DMR_05`, `DMR_TS02A`, `DMR_TS11A`, `DMK_01A`, `DMM_01A`, `DMM_01E`, `DMM_01G`, `DMM_01H`, `DMM_01K`, `DMM_02A`, `DMM_03A`, `DMP_01A`
- `tdm`: `TDMR_01A`–`TDMR_05B` (A and B of each), `TDMR_TS11A`, `TDMK_01A`, `TDMK_01B`, `TDMM_01A`, `TDMM_01B`, `TDMM_01E`–`TDMM_01H`, `TDMM_01K`, `TDMM_01L`, `TDMM_02A`, `TDMM_02B`, `TDMM_03A`, `TDMM_03B`, `TDMP_01A`, `TDMP_01B`
- `tkoth`: `TKHR_01A`–`TKHR_05B`, `TKHR_04`, `TKHR_TS02A`, `TDMR_TS02A`, `TKHK_01A`, `TKHK_01B`, `TKHM_01A`, `TKHM_01B`, `TKHM_01E`–`TKHM_01H`, `TKHM_01K`, `TKHM_01L`, `TKHM_02A`, `TKHM_02B`, `TKHM_03A`, `TKHM_03B`, `TKHP_01A`, `TKHP_01B`
- `koth`: `KHR_01A`, `KHR_02A`, `KHR_03A`, `KHR_04A`, `KHM_01A`, `KHM_01E`, `KHM_01G`, `KHM_02A`, `KHM_03A`
- `sd`: `SDR_01A`–`SDR_05B`, `SDK_01A`, `SDK_01B`, `SDM_01A`, `SDM_01B`, `SDM_01E`–`SDM_01H`, `SDM_01K`, `SDM_01L`, `SDM_02A`, `SDM_02B`, `SDM_03A`, `SDM_03B`, `SDP_01A`, `SDP_01B`
- `ad`: `ADR_01A`–`ADR_05B`, `ADK_01A`, `ADK_01B`, `ADK_02A`, `ADK_02B`, `ADM_01A`, `ADM_01B`, `ADM_01E`–`ADM_01H`, `ADM_02A`, `ADM_02B`, `ADM_03A`, `ADM_03B`, `ADP_01A`, `ADP_01B`, `ADP_11A`, `ADP_11B`
- `ctf`: `CTFR_01A`–`CTFR_05B`, `CTFR_TS11A`, `CTF_04A`, `CTF_04B`, `CTFK_01A`–`CTFK_03B`, `CTFM_01A`, `CTFM_01B`, `CTFM_01E`–`CTFM_01L`, `CTFM_02A`, `CTFM_02B`, `CTFM_03A`, `CTFM_03B`, `CTFM_05A`, `CTFM_05B`, `CTFP_01A`, `CTFP_01B`
- `fb`: `FBR_01A`–`FBR_05B`, `FBR_TS11A`, `FBK_01A`, `FBK_01B`, `FBK_03A`, `FBK_03B`, `FBM_01A`, `FBM_01B`, `FBM_01E`–`FBM_01H`, `FBM_01K`, `FBM_01L`, `FBM_02A`, `FBM_02B`, `FBM_03A`, `FBM_03B`, `FBP_01A`, `FBP_01B`

The configure hook logs the rotation it wrote. Co-op (the single-player and Team Sabre campaign missions) isn't supported.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/deltaforceblackhawkdown:local .
```

---

## License

Delta Force: Black Hawk Down and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
