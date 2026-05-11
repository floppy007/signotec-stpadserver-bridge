# signotec STPadServer (Windows build) running under Wine on Linux.
#
# Copyright (c) 2026 Florian Hesse — comnic IT (https://comnic-it.de)
# License: MIT (see LICENSE in the same directory)
#
# Build phases:
#   1. extract — runs the InstallShield installer briefly under Wine, grabs
#      the extracted MSI from %TEMP%, then 7z's it -> Data1.cab -> cabextract.
#      No signotec binaries are committed to this repo; they are fetched
#      from signotec's public download portal at build time.
#   2. runtime — Ubuntu Jammy + Wine + flat copy of the extracted binaries.

ARG SIGNOPAD_VERSION=3.5.0
ARG SIGNOPAD_URL=https://downloads.signotec.com/signoPAD-API_Web/signotec_signoPAD-API_Web_${SIGNOPAD_VERSION}.exe

# ----------------------------------------------------------------------------
# Stage 1 — extract
# ----------------------------------------------------------------------------
FROM ubuntu:22.04 AS extract

ARG SIGNOPAD_URL
ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wine wine32:i386 winbind xvfb \
        p7zip-full cabextract procps \
    && rm -rf /var/lib/apt/lists/*

ENV WINEPREFIX=/wineprefix \
    WINEARCH=win32 \
    DISPLAY=:99 \
    WINEDEBUG=-all

WORKDIR /work
RUN curl -fsSL -o installer.exe "$SIGNOPAD_URL"

# Wine-Prefix initialisieren + Installer kurz anstossen — der InstallShield-
# Wrapper extrahiert die innere MSI nach %TEMP%, dann beenden wir ihn.
RUN Xvfb :99 -screen 0 1024x768x16 & sleep 1; \
    wineboot --init >/dev/null 2>&1 || true; \
    (wine installer.exe /S 2>/dev/null || true) & \
    INSTALLER_PID=$!; \
    for i in $(seq 1 30); do \
        MSI=$(find /wineprefix/drive_c/users -iname 'signotec_signoPAD-API_Web_*.msi' 2>/dev/null | head -1); \
        if [ -n "$MSI" ]; then \
            cp "$MSI" /work/installer.msi; \
            break; \
        fi; \
        sleep 1; \
    done; \
    kill -9 $INSTALLER_PID 2>/dev/null || true; \
    pkill -9 -f wineserver 2>/dev/null || true; \
    pkill -9 -f Xvfb 2>/dev/null || true; \
    test -f /work/installer.msi

# MSI -> Tabellen + CAB
RUN cd /work && 7z x -y installer.msi -omsi-out >/dev/null

# CAB -> flache Datei-Liste
RUN cd /work && mkdir -p cab-out && cd cab-out && cabextract /work/msi-out/Data1.cab >/dev/null

# Umbenennen — die MSI nutzt Component-Suffixe wie
# "mfc140.dll_x86.F1670FCA_..." → wir wollen flache Namen.
RUN mkdir -p /out && cd /work/cab-out && \
    cp stpadserver.exe                    /out/STPadServer.exe && \
    cp stpadlib.dll                       /out/STPadLib.dll && \
    cp signosignaturecomutils.dll         /out/signoSignatureCOMUtils.dll && \
    cp stpdflib18.dll1                    /out/STPdfLib18.dll && \
    cp stpad.ini                          /out/STPad.ini && \
    cp stpadstores.ini                    /out/STPadStores.ini && \
    for f in *.dll_x86.F1670FCA*; do \
        base=$(basename "$f" | sed 's/\.dll_x86\.F1670FCA.*$//'); \
        cp "$f" "/out/${base}.dll"; \
    done && \
    ls -la /out/

# ----------------------------------------------------------------------------
# Stage 2 — runtime
# ----------------------------------------------------------------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
        wine wine32:i386 wine64 \
        winbind \
        xvfb \
        ca-certificates \
        tini \
        net-tools \
    && rm -rf /var/lib/apt/lists/*

ENV WINEPREFIX=/wineprefix \
    WINEARCH=win32 \
    DISPLAY=:99 \
    WINEDEBUG=-all

WORKDIR /opt/signotec
COPY --from=extract /out/ ./
COPY wine-entrypoint.sh /usr/local/bin/wine-entrypoint.sh

RUN chmod +x /usr/local/bin/wine-entrypoint.sh STPadServer.exe

EXPOSE 49494

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/wine-entrypoint.sh"]
CMD ["0.0.0.0", "49494"]
