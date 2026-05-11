#!/bin/bash
# Entry-point fuer den signotec-Wine-Container.
#
# Wines eigene MSVC-Runtime-Stubs implementieren nicht alle Symbols, die
# signotecs Boost-Asio braucht — wir leiten daher per WINEDLLOVERRIDES auf
# die nativen DLLs aus dem signotec-Bundle um.
set -e

export WINEDLLOVERRIDES="msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,mfc140,mfc140u,vcruntime140,vcruntime140_threads,vccorlib140,concrt140=n,b"

# 1. Wine-Prefix init (idempotent)
if [ ! -d "$WINEPREFIX/drive_c" ]; then
    echo "[wine] init prefix"
    Xvfb :99 -screen 0 1024x768x16 &
    XPID=$!
    sleep 1
    wineboot --init 2>&1 | tail -3 || true
    sleep 1
    kill $XPID 2>/dev/null || true
fi

# 2. Native DLLs nach C:\windows\system32 spiegeln, damit Wines Loader sie
#    bevorzugt vor den eigenen Stubs findet.
SYS32="$WINEPREFIX/drive_c/windows/system32"
mkdir -p "$SYS32"
for dll in /opt/signotec/*.dll; do
    name=$(basename "$dll")
    cp -n "$dll" "$SYS32/$name"
done

# 3. Xvfb fuer Hintergrund-Sessions
Xvfb :99 -screen 0 1024x768x16 &
sleep 1

cd /opt/signotec
echo "[wine] STPadServer.exe ${*}"
exec wine ./STPadServer.exe "$@"
