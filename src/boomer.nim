import os
import strutils
import math
import options

import navigation
import screenshot
import config

import winim/lean
import opengl
import la

type Shader = tuple[path, content: string]

proc readShader(file: string): Shader =
  when nimvm:
    result.path = file
    result.content = slurp result.path
  else:
    result.path = "src" / file
    result.content = readFile result.path

when defined(developer):
  var
    vertexShader = readShader "vert.glsl"
    fragmentShader = readShader "frag.glsl"

  proc reloadShader(shader: var Shader) =
    shader.content = readFile shader.path
else:
  const
    vertexShader = readShader "vert.glsl"
    fragmentShader = readShader "frag.glsl"

proc newShader(shader: Shader, kind: GLenum): GLuint =
  result = glCreateShader(kind)
  var shaderArray = allocCStringArray([shader.content])
  glShaderSource(result, 1, shaderArray, nil)
  glCompileShader(result)
  deallocCStringArray(shaderArray)

  var success: GLint
  var infoLog = newString(512).cstring
  glGetShaderiv(result, GL_COMPILE_STATUS, addr success)
  if not success.bool:
    glGetShaderInfoLog(result, 512, nil, infoLog)
    echo "------------------------------"
    echo "Error during shader compilation: ", shader.path, ". Log:"
    echo infoLog
    echo "------------------------------"

proc newShaderProgram(vertex, fragment: Shader): GLuint =
  result = glCreateProgram()

  var
    vertexShader = newShader(vertex, GL_VERTEX_SHADER)
    fragmentShader = newShader(fragment, GL_FRAGMENT_SHADER)

  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)

  # Without explicit "layout(location = N)" in the shader source, attribute
  # locations are assigned by the driver; pin them so they match the
  # glVertexAttribPointer(0/1, ...) calls regardless of driver behavior.
  glBindAttribLocation(result, 0, "aPos".cstring)
  glBindAttribLocation(result, 1, "aTexCoord".cstring)

  glLinkProgram(result)

  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)

  var success: GLint
  var infoLog = newString(512).cstring
  glGetProgramiv(result, GL_LINK_STATUS, addr success)
  if not success.bool:
    glGetProgramInfoLog(result, 512, nil, infoLog)
    echo infoLog

  glUseProgram(result)

type Flashlight = object
  isEnabled: bool
  shadow: float32
  radius: float32
  deltaRadius: float32

const
  INITIAL_FL_DELTA_RADIUS = 250.0
  FL_DELTA_RADIUS_DECELERATION = 10.0

proc update(flashlight: var Flashlight, dt: float32) =
  if abs(flashlight.deltaRadius) > 1.0:
    flashlight.radius = max(0.0, flashlight.radius + flashlight.deltaRadius * dt)
    flashlight.deltaRadius -= flashlight.deltaRadius * FL_DELTA_RADIUS_DECELERATION * dt

  if flashlight.isEnabled:
    flashlight.shadow = min(flashlight.shadow + 6.0 * dt, 0.8)
  else:
    flashlight.shadow = max(flashlight.shadow - 6.0 * dt, 0.0)

proc draw(screenshot: Screenshot, camera: Camera, shader, vao, texture: GLuint,
          windowSize: Vec2f, mouse: Mouse, flashlight: Flashlight, mirror: bool) =
  glClearColor(0.1, 0.1, 0.1, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  glUseProgram(shader)

  glUniform2f(glGetUniformLocation(shader, "cameraPos".cstring), camera.position[0], camera.position[1])
  glUniform1f(glGetUniformLocation(shader, "cameraScale".cstring), camera.scale)
  glUniform2f(glGetUniformLocation(shader, "screenshotSize".cstring),
              screenshot.width.float32,
              screenshot.height.float32)
  glUniform2f(glGetUniformLocation(shader, "windowSize".cstring),
              windowSize.x.float32,
              windowSize.y.float32)
  glUniform2f(glGetUniformLocation(shader, "cursorPos".cstring),
              mouse.curr.x.float32,
              mouse.curr.y.float32)
  glUniform1f(glGetUniformLocation(shader, "flShadow".cstring), flashlight.shadow)
  glUniform1f(glGetUniformLocation(shader, "flRadius".cstring), flashlight.radius)
  glUniform1i(glGetUniformLocation(shader, "mirror".cstring), if mirror: 1 else: 0)

  glBindVertexArray(vao)
  glDrawElements(GL_TRIANGLES, count = 6, GL_UNSIGNED_INT, indices = nil)

proc getCursorPosition(): Vec2f =
  var p: POINT
  discard GetCursorPos(addr p)
  result.x = p.x.float32
  result.y = p.y.float32

when defined(select):
  proc selectWindow(): HWND =
    echo "Please select window:"
    discard SetCursor(LoadCursor(0, IDC_CROSS))

    # Wait out any click that was already in progress when we started polling.
    while (GetAsyncKeyState(VK_LBUTTON) and 0x8000) != 0:
      sleep(10)
    while (GetAsyncKeyState(VK_LBUTTON) and 0x8000) == 0:
      sleep(10)

    var pt: POINT
    discard GetCursorPos(addr pt)
    result = GetAncestor(WindowFromPoint(pt), GA_ROOT)
    if result == 0:
      result = GetDesktopWindow()

# Global state the WndProc needs access to. Win32's callback-based message
# loop has no room for extra context pointers in this minimal setup.
var
  gMouse: Mouse
  gCamera: Camera
  gConfig: Config
  gFlashlight: Flashlight
  gQuitting = false
  gDt: float32 = 1.0 / 60.0 # previous frame's duration, refreshed once per loop iteration

proc wndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_DESTROY:
    PostQuitMessage(0)
    return 0

  of WM_CLOSE:
    gQuitting = true
    return 0

  of WM_MOUSEMOVE:
    let x = float32(cast[int16](lParam and 0xFFFF))
    let y = float32(cast[int16]((lParam shr 16) and 0xFFFF))
    gMouse.curr = vec2(x, y)
    if gMouse.drag:
      let delta = world(gCamera, gMouse.prev) - world(gCamera, gMouse.curr)
      gCamera.position += delta
      gCamera.velocity = delta / gDt
    gMouse.prev = gMouse.curr
    return 0

  of WM_LBUTTONDOWN:
    gMouse.prev = gMouse.curr
    gMouse.drag = true
    gCamera.velocity = vec2(0.0, 0.0)
    SetCapture(hwnd)
    return 0

  of WM_LBUTTONUP:
    gMouse.drag = false
    discard ReleaseCapture()
    return 0

  of WM_MOUSEWHEEL:
    let delta = cast[int16]((wParam shr 16) and 0xFFFF)
    let ctrlDown = (GetKeyState(VK_CONTROL) and 0x8000) != 0
    if ctrlDown and gFlashlight.isEnabled:
      gFlashlight.deltaRadius += (if delta > 0: INITIAL_FL_DELTA_RADIUS else: -INITIAL_FL_DELTA_RADIUS)
    else:
      gCamera.deltaScale += (if delta > 0: gConfig.scrollSpeed else: -gConfig.scrollSpeed)
      gCamera.scalePivot = gMouse.curr
    return 0

  else:
    return DefWindowProc(hwnd, msg, wParam, lParam)

proc main() =
  let boomerDir = getConfigDir() / "boomer"
  var configFile = boomerDir / "config"
  var windowed = false
  var delaySec = 0.0

  block:
    proc versionQuit() =
      const hash = gorgeEx("git rev-parse HEAD")
      quit "boomer-$#" % [if hash.exitCode == 0: hash.output[0 .. 7] else: "unknown"]
    proc usageQuit() =
      quit """Usage: boomer [OPTIONS]
  -d, --delay <seconds: float>  delay execution of the program by provided <seconds>
  -h, --help                    show this help and exit
      --new-config [filepath]   generate a new default config at [filepath]
  -c, --config <filepath>       use config at <filepath>
  -V, --version                 show the current version and exit
  -w, --windowed                windowed mode instead of fullscreen"""
    var i = 1
    while i <= paramCount():
      let arg = paramStr(i)

      template asParam(paramVar: untyped, body: untyped) =
        if i + 1 > paramCount():
          echo "No value is provided for $#" % [arg]
          usageQuit()
        let paramVar = paramStr(i + 1)
        body
        i += 2

      template asFlag(body: untyped) =
        body
        i += 1

      template asOptionalParam(paramVar: untyped, body: untyped) =
        let paramVar = block:
          var resultVal = none(string)
          if i + 1 <= paramCount():
            let param = paramStr(i + 1)
            if len(param) > 0 and param[0] != '-':
              resultVal = some(param)
          resultVal
        body
        if paramVar.isNone:
          i += 1
        else:
          i += 2

      case arg
      of "-d", "--delay":
        asParam(delayParam):
          delaySec = parseFloat(delayParam)
      of "-w", "--windowed":
        asFlag():
          windowed = true
      of "-h", "--help":
        asFlag():
          usageQuit()
      of "-V", "--version":
        asFlag():
          versionQuit()
      of "--new-config":
        asOptionalParam(configName):
          let newConfigPath = configName.get(configFile)

          createDir(newConfigPath.splitFile.dir)
          if newConfigPath.fileExists:
            stdout.write("File ", newConfigPath, " already exists. Replace it? [yn] ")
            if stdin.readChar != 'y':
              quit "Disaster prevented"

          generateDefaultConfig(newConfigPath)
          quit "Generated config at $#" % [newConfigPath]
      of "-c", "--config":
        asParam(configParam):
          configFile = configParam
      else:
        echo "Unknown flag `$#`" % [arg]
        usageQuit()
  sleep(floor(delaySec * 1000).int)

  gConfig = defaultConfig
  if fileExists configFile:
    gConfig = loadConfig(configFile)
  else:
    stderr.writeLine configFile & " doesn't exist. Using default values. "

  echo "Using config: ", gConfig

  when defined(select):
    var trackingWindow = selectWindow()
  else:
    var trackingWindow = GetDesktopWindow()

  # Must happen before our own window is created: once it's shown it covers
  # the whole screen with its own (still unpainted, i.e. black) surface, so
  # capturing the screen any later would just capture ourselves.
  var shot = newScreenshot(trackingWindow)
  defer: shot.destroy()

  let hInstance = GetModuleHandle(nil)
  var className = +$"BoomerWindowClass"
  var windowTitle = +$"boomer"

  var wc: WNDCLASSEX
  wc.cbSize = UINT(sizeof(WNDCLASSEX))
  wc.style = CS_OWNDC
  wc.lpfnWndProc = wndProc
  wc.hInstance = hInstance
  wc.lpszClassName = cast[LPCWSTR](&className)
  wc.hCursor = LoadCursor(0, IDC_ARROW)
  discard RegisterClassEx(addr wc)

  let screenWidth = GetSystemMetrics(SM_CXSCREEN)
  let screenHeight = GetSystemMetrics(SM_CYSCREEN)

  let style = if windowed: WS_OVERLAPPEDWINDOW else: WS_POPUP
  let exStyle = if windowed: 0.DWORD else: WS_EX_TOPMOST.DWORD

  let hwnd = CreateWindowEx(
    exStyle, cast[LPCWSTR](&className), cast[LPCWSTR](&windowTitle), style.DWORD,
    0, 0, screenWidth, screenHeight,
    0, 0, hInstance, nil)
  if hwnd == 0:
    quit "Failed to create window"

  discard ShowWindow(hwnd, SW_SHOW)
  discard UpdateWindow(hwnd)

  let hdc = GetDC(hwnd)

  var pfd: PIXELFORMATDESCRIPTOR
  pfd.nSize = WORD(sizeof(PIXELFORMATDESCRIPTOR))
  pfd.nVersion = 1
  pfd.dwFlags = PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER
  pfd.iPixelType = PFD_TYPE_RGBA
  pfd.cColorBits = 24
  pfd.cDepthBits = 24
  pfd.iLayerType = PFD_MAIN_PLANE

  let pixelFormat = ChoosePixelFormat(hdc, addr pfd)
  if pixelFormat == 0:
    quit "No appropriate pixel format found"
  discard SetPixelFormat(hdc, pixelFormat, addr pfd)

  let glrc = wglCreateContext(hdc)
  discard wglMakeCurrent(hdc, glrc)
  # Declared before the GL object defers below so it runs *after* them
  # (Nim defers fire in reverse order) -- the context must still be
  # current when glDelete* runs during cleanup.
  defer:
    discard wglMakeCurrent(hdc, 0)
    discard wglDeleteContext(glrc)
    discard ReleaseDC(hwnd, hdc)
    discard DestroyWindow(hwnd)

  loadExtensions()

  echo "GL_VERSION: ", cast[cstring](glGetString(GL_VERSION))
  echo "GL_RENDERER: ", cast[cstring](glGetString(GL_RENDERER))
  echo "GL_SHADING_LANGUAGE_VERSION: ", cast[cstring](glGetString(GL_SHADING_LANGUAGE_VERSION))

  var shaderProgram = newShaderProgram(vertexShader, fragmentShader)

  let w = shot.width.float32
  let h = shot.height.float32
  var
    vao, vbo, ebo: GLuint
    vertices = [
      # Position            Texture coords
      [GLfloat    w,     0, 1.0, 1.0], # Top right
      [GLfloat    w,     h, 1.0, 0.0], # Bottom right
      [GLfloat    0,     h, 0.0, 0.0], # Bottom left
      [GLfloat    0,     0, 0.0, 1.0]  # Top left
    ]
    indices = [GLuint(0), 1, 3,
                      1,  2, 3]

  glGenVertexArrays(1, addr vao)
  glGenBuffers(1, addr vbo)
  glGenBuffers(1, addr ebo)
  defer:
    glDeleteVertexArrays(1, addr vao)
    glDeleteBuffers(1, addr vbo)
    glDeleteBuffers(1, addr ebo)

  glBindVertexArray(vao)

  glBindBuffer(GL_ARRAY_BUFFER, vbo)
  glBufferData(GL_ARRAY_BUFFER, size = GLsizeiptr(sizeof(vertices)),
               addr vertices, GL_STATIC_DRAW)

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, size = GLsizeiptr(sizeof(indices)),
               addr indices, GL_STATIC_DRAW)

  var stride = GLsizei(vertices[0].len * sizeof(GLfloat))

  glVertexAttribPointer(0, 2, cGL_FLOAT, false, stride, cast[pointer](0))
  glEnableVertexAttribArray(0)

  glVertexAttribPointer(1, 2, cGL_FLOAT, false, stride, cast[pointer](2 * sizeof(GLfloat)))
  glEnableVertexAttribArray(1)

  var texture = 0.GLuint
  glGenTextures(1, addr texture)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, texture)

  glTexImage2D(GL_TEXTURE_2D,
               0,
               GL_RGB.GLint,
               shot.width,
               shot.height,
               0,
               GL_BGRA,
               GL_UNSIGNED_BYTE,
               shot.data)
  glGenerateMipmap(GL_TEXTURE_2D)

  glUniform1i(glGetUniformLocation(shaderProgram, "tex".cstring), 0)

  glEnable(GL_TEXTURE_2D)

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER)

  let pos = getCursorPosition()
  gMouse = Mouse(curr: pos, prev: pos)
  gCamera = Camera(scale: 1.0)
  gFlashlight = Flashlight(isEnabled: false, radius: 200.0)
  var mirror = false

  var freq, prevCounter: LARGE_INTEGER
  discard QueryPerformanceFrequency(addr freq)
  discard QueryPerformanceCounter(addr prevCounter)
  var prevTicks = prevCounter.QuadPart

  var msg: MSG
  while not gQuitting:
    var counter: LARGE_INTEGER
    discard QueryPerformanceCounter(addr counter)
    let dt = (counter.QuadPart - prevTicks).float / freq.QuadPart.float
    prevTicks = counter.QuadPart
    if dt > 0:
      gDt = dt.float32

    while PeekMessage(addr msg, 0, 0, 0, PM_REMOVE) != 0:
      if msg.message == WM_QUIT:
        gQuitting = true
      case msg.message
      of WM_KEYDOWN:
        case msg.wParam
        of VK_OEM_PLUS, VK_ADD:
          gCamera.deltaScale += gConfig.scrollSpeed
          gCamera.scalePivot = gMouse.curr
        of VK_OEM_MINUS, VK_SUBTRACT:
          gCamera.deltaScale -= gConfig.scrollSpeed
          gCamera.scalePivot = gMouse.curr
        of ord('0'):
          gCamera.scale = 1.0
          gCamera.deltaScale = 0.0
          gCamera.position = vec2(0.0'f32, 0.0)
          gCamera.velocity = vec2(0.0'f32, 0.0)
          mirror = false
        of ord('Q'), VK_ESCAPE:
          gQuitting = true
        of ord('R'):
          when defined(developer):
            if (GetKeyState(VK_CONTROL) and 0x8000) != 0:
              echo "------------------------------"
              echo "RELOADING SHADERS"
              try:
                reloadShader(vertexShader)
                reloadShader(fragmentShader)
                let newShaderProgram = newShaderProgram(vertexShader, fragmentShader)
                glDeleteProgram(shaderProgram)
                shaderProgram = newShaderProgram
                echo "Shader program ID: ", shaderProgram
              except IOError:
                echo "Could not reload the shaders"
              echo "------------------------------"
            else:
              if configFile.len > 0 and fileExists(configFile):
                gConfig = loadConfig(configFile)
          else:
            if configFile.len > 0 and fileExists(configFile):
              gConfig = loadConfig(configFile)
        of ord('M'):
          gCamera.position[0] += shot.width.float/gCamera.scale - 2*(gMouse.curr[0]/gCamera.scale + gCamera.position[0])
          mirror = not mirror
        of ord('F'):
          gFlashlight.isEnabled = not gFlashlight.isEnabled
        else:
          discard
      else:
        discard
      discard TranslateMessage(addr msg)
      discard DispatchMessage(addr msg)

    var rect: RECT
    discard GetClientRect(hwnd, addr rect)
    let windowSize = vec2((rect.right - rect.left).float32, (rect.bottom - rect.top).float32)
    glViewport(0, 0, rect.right - rect.left, rect.bottom - rect.top)

    gCamera.update(gConfig, dt, gMouse, windowSize)
    gFlashlight.update(dt.float32)

    shot.draw(gCamera, shaderProgram, vao, texture,
              windowSize, gMouse, gFlashlight, mirror)

    discard SwapBuffers(hdc)

    when defined(live):
      shot.refresh()
      let lw = shot.width.float32
      let lh = shot.height.float32
      let newVertices = [
        # Position             Texture coords
        [GLfloat    lw,     0, 1.0, 1.0], # Top right
        [GLfloat    lw,    lh, 1.0, 0.0], # Bottom right
        [GLfloat     0,    lh, 0.0, 0.0], # Bottom left
        [GLfloat     0,     0, 0.0, 1.0]  # Top left
      ]
      glBindBuffer(GL_ARRAY_BUFFER, vbo)
      glBufferData(GL_ARRAY_BUFFER, size = GLsizeiptr(sizeof(newVertices)),
                   addr newVertices, GL_STATIC_DRAW)
      glBindTexture(GL_TEXTURE_2D, texture)
      glTexImage2D(GL_TEXTURE_2D,
                   0,
                   GL_RGB.GLint,
                   shot.width,
                   shot.height,
                   0,
                   GL_BGRA,
                   GL_UNSIGNED_BYTE,
                   shot.data)

main()
