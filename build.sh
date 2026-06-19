#!/bin/bash

nim c --os:windows --cpu:amd64 --cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc -d:mingw -d:release -o:boomer.exe src/boomer.nim
# nim c --os:windows --cpu:amd64 --cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc -d:mingw -d:release -d:select -d:live -o:boomer.exe src/boomer.nim
