#!/usr/bin/env bash
# Uso: build_deb.sh <versão> <arquitetura deb: amd64|arm64> <pasta do bundle> <pasta de saída> <rótulo: X64|ARM64>
set -euo pipefail
VERSION="$1"; ARCH="$2"; BUNDLE="$3"; OUT="$4"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(mktemp -d)"

install -d "$ROOT/opt/spotifin" "$ROOT/usr/bin" \
  "$ROOT/usr/share/applications" \
  "$ROOT/usr/share/icons/hicolor/192x192/apps" "$ROOT/DEBIAN"
cp -a "$BUNDLE"/. "$ROOT/opt/spotifin/"
ln -s /opt/spotifin/spotifin "$ROOT/usr/bin/spotifin"
install -m 644 "$HERE/spotifin.desktop" "$ROOT/usr/share/applications/spotifin.desktop"
install -m 644 "$HERE/spotifin.png" "$ROOT/usr/share/icons/hicolor/192x192/apps/spotifin.png"

SIZE_KB=$(du -sk "$ROOT/opt" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<CTRL
Package: spotifin
Version: $VERSION
Section: sound
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE_KB
Depends: libgtk-3-0, libmpv2 | libmpv1, libsecret-1-0, libjsoncpp25 | libjsoncpp24 | libjsoncpp1
Recommends: gnome-keyring | kwalletmanager, zenity | kdialog
Maintainer: Eduardo Valente <valenteeduardo39@gmail.com>
Homepage: https://github.com/
Description: Spotify-style music player for your Jellyfin library
 Spotifin plays only the music in your own Jellyfin server, with offline
 downloads, playlists, favorites and a Spotify-like interface.
CTRL

mkdir -p "$OUT"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT/Spotifin_Linux$5_v${VERSION}.deb"
rm -rf "$ROOT"
