#!/bin/sh
# Cross-compile Grove for Windows x64 from Linux and package a game as a zip.
#   tools/windows/build.sh [game] [title]   (default game: carl4; title names the launcher .bat)  ->  dist/<game>-windows.zip
# Needs zig (on PATH, or ZIG=/path/to/zig). Downloads GLFW 3.4 source once into ~/.cache/grove-win.
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
GAME=${1:-carl4}
W=$ROOT/tools/windows
export ZIG=${ZIG:-$(command -v zig || echo "$HOME/.local/opt/zig-x86_64-linux-0.17.0/zig")}
DEPS=${GROVE_WIN_DEPS:-$HOME/.cache/grove-win}
mkdir -p "$DEPS"

# ---- GLFW (static, built once)
if [ ! -f "$DEPS/glfw/lib/libglfw3.a" ]; then
  [ -d "$DEPS/glfw-3.4" ] || {
    curl -sSLo "$DEPS/glfw.zip" https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.zip
    (cd "$DEPS" && unzip -q glfw.zip)
  }
  cmake -S "$DEPS/glfw-3.4" -B "$DEPS/glfw-build" -DCMAKE_TOOLCHAIN_FILE="$W/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF \
    -DCMAKE_INSTALL_PREFIX="$DEPS/glfw" >/dev/null
  cmake --build "$DEPS/glfw-build" -j"$(nproc)"
  cmake --install "$DEPS/glfw-build" >/dev/null
fi

# ---- LuaJIT (static, built once from a copy of third_party/luajit so the Linux lib is untouched)
if [ ! -f "$DEPS/libluajit.a" ]; then
  rm -rf "$DEPS/luajit"
  cp -r third_party/luajit "$DEPS/luajit"
  make -C "$DEPS/luajit/src" clean >/dev/null
  make -C "$DEPS/luajit/src" -j"$(nproc)" HOST_CC="gcc" TARGET_SYS=Windows BUILDMODE=static \
    CROSS= STATIC_CC="$W/zig-cc" DYNAMIC_CC="$W/zig-cc" TARGET_LD="$W/zig-cc" \
    TARGET_AR="$W/zig-ar rcus" TARGET_STRIP=true libluajit.a
  cp "$DEPS/luajit/src/libluajit.a" "$DEPS/libluajit.a"
fi

# ---- engine
cmake -S . -B build-win -DCMAKE_TOOLCHAIN_FILE="$W/toolchain.cmake" -DCMAKE_BUILD_TYPE=Release \
  -DGROVE_WIN_DEPS="$DEPS" >/dev/null
cmake --build build-win -j"$(nproc)"

# ---- package: <game>/bin/grove.exe, engine/, games/<game>/, plus a launcher
OUT=dist/$GAME-windows
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/games"
cp build-win/bin/grove.exe "$OUT/bin/"
cp -r engine "$OUT/engine"
cp -r "games/$GAME" "$OUT/games/$GAME"
rm -rf "$OUT/games/$GAME/screenshots" "$OUT/games/$GAME/tools"
NAME=${2:-$(echo "$GAME" | tr a-z A-Z)}
printf '@echo off\r\ncd /d "%%~dp0"\r\nstart "" "bin\\grove.exe" "games\\%s"\r\n' "$GAME" > "$OUT/Play $NAME.bat"
printf 'Double-click "Play %s.bat" (or bin\\grove.exe) to play.\r\nNeeds a graphics card with OpenGL 4.5 (any GPU from the last ~10 years).\r\nF11 toggles fullscreen.\r\n' "$NAME" > "$OUT/README.txt"
(cd dist && rm -f "$GAME-windows.zip" && zip -qr "$GAME-windows.zip" "$GAME-windows")
echo "built dist/$GAME-windows.zip"
