#!/bin/sh
# Builds helper/DmorphHelper.dll (32-bit, like WoW 1.12) with MinGW-w64:
#   sudo apt-get install gcc-mingw-w64-i686   (Debian/Ubuntu)
#   sh helper/build.sh
# MinHook (helper/minhook, BSD 2-clause) is compiled in; the DLL only needs
# KERNEL32.dll and msvcrt.dll, which every Windows has.
set -e
cd "$(dirname "$0")"
i686-w64-mingw32-gcc -std=c11 -O2 -s -shared -Wall -Wextra -Wno-cast-function-type -Wno-unused-parameter \
  -Iminhook/include -o DmorphHelper.dll \
  DmorphHelper.c minhook/src/buffer.c minhook/src/hook.c minhook/src/trampoline.c minhook/src/hde/hde32.c \
  -static-libgcc
echo "built $(pwd)/DmorphHelper.dll"
