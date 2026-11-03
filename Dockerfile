# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Delta Force: Black Hawk Down (+ Team Sabre)
#     v1.5.0.5 install (the folder holding dfbhd.exe and the .pff files) in /config/Server, or
#     set DFBHD_ARCHIVE_URL to a zip of one
#   - dfbhd.exe has no command-line server mode. `dfbhd.exe /autorestart` re-hosts the game saved
#     in autores.bin, so the configure hook writes the DFBHD_* settings into dfv.cfg and builds
#     autores.bin from it (game type, map rotation) on every start
#   - The game opens a 640x480 fullscreen Direct3D window even as a dedicated server, so it runs
#     on a 640x480 virtual display
# ----------------------------
ENV DFBHD_ARCHIVE_URL="" \
    DFBHD_GAME_TYPE="tdm" \
    DFBHD_MAPS="" \
    DFBHD_PORT="17479" \
    DFBHD_SERVER_NAME="Delta Force Server" \
    DFBHD_MESSAGE="" \
    DFBHD_MAX_PLAYERS="32" \
    DFBHD_PASSWORD="" \
    DFBHD_TIME_LIMIT="" \
    DFBHD_SCORE_LIMIT="" \
    DFBHD_RESPAWN_TIME="" \
    DFBHD_CONFIG="" \
    WINE_XVFB="true" \
    WINE_XVFB_SCREEN="640x480x24" \
    START_EXE="/usr/local/bin/dfbhd-server" \
    START_ARGS=""

COPY Scripts/dfbhd-server /usr/local/bin/dfbhd-server
RUN chmod +x /usr/local/bin/dfbhd-server

COPY Hooks/ "${BASE_HOOKS}/"

# 17479/udp: game, LAN browser replies (DFBHD_PORT)
EXPOSE 17479/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
