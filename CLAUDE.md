# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 7 port of [tsoding/boomer](https://github.com/tsoding/boomer), a fullscreen screen-zoomer ("zoomer application for boomers"). The original is Nim + X11 + GLX, Linux-only. This port replaces every X11/GLX call with the Win32/GDI/WGL equivalent; the math/config/shader code is carried over unmodified. There is no upstream relationship — this is a from-scratch reimplementation of the platform layer guided by the original's behavior.

## Build

Cross-compiling from Linux to Windows via mingw-w64 (no native Windows toolchain in this environment):

```sh
./build.sh
```

Equivalent to running directly:

```sh
nim c --os:windows --cpu:amd64 --cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc -d:mingw -d:release -o:boomer.exe src/boomer.nim
```

Optional compile-time feature flags (`-d:xxx`), combine as needed:
- `-d:select` — prompt to click a window at startup and track only that window instead of the whole desktop
- `-d:live` — recapture and re-upload the tracked region every frame instead of a single static screenshot
- `-d:developer` — load shaders from `src/*.glsl` at runtime instead of baking them into the binary at compile time, and enable `Ctrl+R` to hot-reload them. Requires running the exe from a directory that has a `src/` subfolder alongside it — not meant for distribution.

There is no test suite. Verifying a change means cross-compiling, then actually running `boomer.exe` on a real Windows box or VM — see "Known driver pitfalls" below before assuming a black screen is a code bug.

`src/boomer.nim.cfg` bakes in `--app:gui` so the resulting exe never pops a console window when launched normally (double-click/shortcut), but still prints to stdout/stderr when run from an existing terminal (cmd/PowerShell/Git Bash), since a GUI-subsystem process inherits the launching console's handles instead of allocating its own.

## Architecture

`src/boomer.nim` is the entry point and owns everything Win32: window class registration, the `WS_POPUP`+`WS_EX_TOPMOST` fullscreen overlay window, WGL context creation, the GL shader/VAO/texture setup, and the message loop. There's no abstraction layer between this and Win32 — winim (`winim/lean`) is called directly.

`src/screenshot.nim` wraps GDI screen capture: `CreateDIBSection` + `BitBlt` into a top-down 32bpp BGRA buffer, exposed as `Screenshot.data: ptr UncheckedArray[uint8]` for direct upload via `glTexImage2D(..., GL_BGRA, ...)`. `newScreenshot(hwnd)` captures either the full virtual desktop (when `hwnd == GetDesktopWindow()`) or a specific window's client area. `refresh()` re-captures in place, recreating the DIB only if the source size changed — used by `-d:live`. `saveToBMP`/`saveToPPM` are debugging aids (write the raw capture to disk, bypassing the GL pipeline entirely) — not called anywhere in `main()`, kept around for the next time something needs diagnosing this way.

`src/navigation.nim` (`Camera`/`Mouse` + `update()`) and `src/la.nim` (`Vec2f` math) are unmodified two-line ports of the original — `navigation.update()` had its now-dead `image: PXImage` parameter dropped since it was never read by the original's body either. `src/config.nim` (the `key = value` config file format under `%APPDATA%\boomer\config`, via Nim's own cross-platform `getConfigDir()`) is untouched from upstream.

`src/vert.glsl`/`src/frag.glsl` are also untouched from upstream. They expect vertex attribute locations 0 = `aPos`, 1 = `aTexCoord` without declaring `layout(location=...)` in the source — `boomer.nim`'s `newShaderProgram` pins these explicitly via `glBindAttribLocation` before linking, because GLSL leaves attribute-location auto-assignment up to the driver, and it does not reliably land on 0/1 in the order the app assumes on every driver (see below).

Per-frame state (`gMouse`, `gCamera`, `gConfig`, `gFlashlight`, `gQuitting`, `gDt`) lives in module-level globals because `wndProc` is a `{.stdcall.}` callback with a fixed Win32 signature — there's nowhere to thread an app-context pointer through without `SetWindowLongPtr(GWLP_USERDATA, ...)`, which wasn't worth the indirection for a single-window app. `gDt` specifically holds the *previous* frame's duration so `WM_MOUSEMOVE` can convert a per-event pixel delta into a units/second velocity at the moment it happens, rather than the main loop retroactively rescaling `gCamera.velocity` every iteration — an earlier version did the latter and it compounded division every frame the mouse didn't move, exploding the velocity and flinging the camera into the void (visible as a black screen on release, since `GL_CLAMP_TO_BORDER`'s default border color is black).

### Startup ordering that matters

`newScreenshot()` is called *before* the overlay window is created. The overlay is a fullscreen `WS_POPUP`+`WS_EX_TOPMOST` window with no painted content until the first `SwapBuffers`; capturing the screen any later would capture our own (still-black) window instead of the desktop underneath it.

Cleanup order inside `main()` is built from `defer` blocks specifically so it runs in reverse-of-declaration order: GL object deletion (`glDeleteVertexArrays`/`glDeleteBuffers`) is declared *after* the WGL-context-teardown defer, so it fires *before* it — the context must still be current when those `glDelete*` calls run. Getting this backwards doesn't fail loudly: it raises a delayed `GL_INVALID_OPERATION` (caught by the `opengl` wrapper's automatic `glGetError` check) at whatever the next GL call happens to be, which can look unrelated to the real cause.

### Known driver pitfalls (Mesa/SVGA3D on VMware in particular)

A window created with `WS_EX_LAYERED` does not reliably composite OpenGL `SwapBuffers` output through every driver — some accept the calls without error and simply never show anything, leaving the window stuck on whatever it was initialized to (black). This app doesn't need layering at all (it's always fully opaque), so `WS_EX_LAYERED`/`SetLayeredWindowAttributes` were removed rather than worked around — don't reintroduce them for opacity tricks.

When chasing a black screen with no GL error and no crash, check in this order: (1) `GL_VERSION`/`GL_RENDERER`/`GL_SHADING_LANGUAGE_VERSION` (logged at startup) to rule out an unexpectedly old/software context, (2) dump `Screenshot.data` via `saveToBMP` to confirm GDI capture itself isn't returning blank/black data, (3) only then suspect the GL draw call itself (attribute binding, uniform values, texture format).
