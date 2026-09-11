# Boomer (Windows 7 port)

Zoomer application for Windows. A fullscreen overlay that lets you zoom and pan around a screenshot of your desktop — useful for presentations, streaming, or just squinting at small text.

This is a Windows port of https://github.com/tsoding/boomer.git, which is Linux/X11-only. The math, config format, and shaders are carried over unchanged; the entire windowing/capture/OpenGL-context layer has been rewritten against Win32, GDI, and WGL.

## Dependencies

Building requires [Nim](https://nim-lang.org/) and the following nimble packages:

```console
$ nimble install winim opengl
```

## Quick Start

Cross-compiling from Linux with mingw-w64:

```console
$ ./build.sh
```

which is shorthand for:

```console
$ nim c --os:windows --cpu:amd64 --cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc -d:mingw -d:release -o:boomer.exe src/boomer.nim
```

Copy `boomer.exe` to the Windows machine and run it:

```console
> boomer.exe
```

The compiled binary uses the GUI subsystem, so launching it normally (double-click, shortcut) never pops up a console window. Running it from an existing terminal (cmd/PowerShell/Git Bash) still shows its log output there.

## Controls

| Control                                   | Description                                                   |
|--------------------------------------------|-----------------------------------------------------------------|
| <kbd>0</kbd>                              | Reset the application state (position, scale, velocity, etc). |
| <kbd>q</kbd> or <kbd>ESC</kbd>            | Quit the application.                                          |
| <kbd>r</kbd>                              | Reload configuration.                                          |
| <kbd>m</kbd>                              | Mirror the image.                                              |
| <kbd>Ctrl</kbd> + <kbd>r</kbd>            | Reload the shaders (only for `-d:developer` builds).           |
| <kbd>f</kbd>                              | Toggle flashlight effect.                                       |
| Drag with left mouse button               | Move the image around.                                          |
| Scroll wheel or <kbd>=</kbd>/<kbd>-</kbd> | Zoom in/out.                                                    |
| <kbd>Ctrl</kbd> + Scroll wheel            | Change the radius of the flashlight.                            |

## Configuration

Configuration file is located at `%APPDATA%\boomer\config` and has roughly the following format:

```
<param-1> = <value-1>
<param-2> = <value-2>
# comment
<param-3> = <value-3>
```

You can generate a new config with `boomer.exe --new-config`.

Supported parameters:

| Name           | Description                                        |
|----------------|-----------------------------------------------------|
| min_scale      | The smallest it can get when zooming out            |
| scroll_speed   | How quickly you can zoom in/out by scrolling        |
| drag_friction  | How quickly the movement slows down after dragging  |
| scale_friction | How quickly the zoom slows down after scrolling     |

## Command-line flags

```
Usage: boomer [OPTIONS]
  -d, --delay <seconds: float>  delay execution of the program by provided <seconds>
  -h, --help                    show this help and exit
      --new-config [filepath]   generate a new default config at [filepath]
  -c, --config <filepath>       use config at <filepath>
  -V, --version                 show the current version and exit
  -w, --windowed                windowed mode instead of fullscreen
```

## Experimental Features Compilation Flags

Pass these to the `nim c` invocation in `build.sh` to enable optional behavior:

| Flag             | Description                                                                                                                          |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| `-d:select`      | At startup, click a window to track only that window instead of the full desktop.                                                     |
| `-d:live`        | Recapture and re-upload the tracked region every frame instead of taking a single static screenshot.                                   |
| `-d:developer`   | Load shaders from `src/*.glsl` at runtime instead of baking them into the binary, and enable `Ctrl+R` to hot-reload them. Requires running the exe from a directory with a `src/` subfolder alongside it — not suitable for distribution. |

## Known limitations

- No equivalent of the original's `-d:mitshm` flag — that optimization is specific to X11's MIT-SHM extension and has no counterpart needed on the GDI capture path used here.
- Tested via cross-compilation and manual runs on a Windows 7 VM (VMware, Mesa/SVGA3D driver). Behavior on other GPU drivers hasn't been verified.

## References

- Original Linux version: https://github.com/tsoding/boomer.git
- [winim](https://github.com/khchen/winim) — Win32/COM/CLR bindings for Nim
- https://learn.microsoft.com/en-us/windows/win32/opengl/opengl-functions
- https://learn.microsoft.com/en-us/windows/win32/gdi/capturing-an-image

## 💖 Support & Donations


| Coin | Network | Address |
| :--- | :--- | :--- |
| **SOL** | Solana | `GnXfjr5Kq4tpijwfeMbtnqicLFptXXP5rV79axB1M6F5` |
