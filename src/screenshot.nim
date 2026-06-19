import winim/lean

type Screenshot* = object
  hwnd: HWND
  x*, y*: int32
  width*, height*: int32
  hbmp: HBITMAP
  hdcMem: HDC
  data*: ptr UncheckedArray[uint8] # top-down BGRA, 4 bytes/pixel

proc captureRect(hwnd: HWND): tuple[x, y, w, h: int32] =
  if hwnd == GetDesktopWindow():
    result.x = GetSystemMetrics(SM_XVIRTUALSCREEN)
    result.y = GetSystemMetrics(SM_YVIRTUALSCREEN)
    result.w = GetSystemMetrics(SM_CXVIRTUALSCREEN)
    result.h = GetSystemMetrics(SM_CYVIRTUALSCREEN)
  else:
    var rect: RECT
    discard GetClientRect(hwnd, addr rect)
    var origin = POINT(x: 0, y: 0)
    discard ClientToScreen(hwnd, addr origin)
    result.x = origin.x
    result.y = origin.y
    result.w = rect.right - rect.left
    result.h = rect.bottom - rect.top

proc grab(screenshot: var Screenshot) =
  let hdcScreen = GetDC(0)
  defer: discard ReleaseDC(0, hdcScreen)

  screenshot.hdcMem = CreateCompatibleDC(hdcScreen)

  var bmi: BITMAPINFO
  bmi.bmiHeader.biSize = DWORD(sizeof(BITMAPINFOHEADER))
  bmi.bmiHeader.biWidth = screenshot.width
  bmi.bmiHeader.biHeight = -screenshot.height # top-down DIB
  bmi.bmiHeader.biPlanes = 1
  bmi.bmiHeader.biBitCount = 32
  bmi.bmiHeader.biCompression = BI_RGB

  var bits: pointer
  screenshot.hbmp = CreateDIBSection(
    hdcScreen, addr bmi, DIB_RGB_COLORS, addr bits, 0, 0)
  discard SelectObject(screenshot.hdcMem, screenshot.hbmp)
  screenshot.data = cast[ptr UncheckedArray[uint8]](bits)

  discard BitBlt(
    screenshot.hdcMem, 0, 0, screenshot.width, screenshot.height,
    hdcScreen, screenshot.x, screenshot.y, SRCCOPY)

proc destroy*(screenshot: Screenshot) =
  discard DeleteObject(screenshot.hbmp)
  discard DeleteDC(screenshot.hdcMem)

proc newScreenshot*(hwnd: HWND): Screenshot =
  result.hwnd = hwnd
  let rect = captureRect(hwnd)
  result.x = rect.x
  result.y = rect.y
  result.width = rect.w
  result.height = rect.h
  result.grab()

proc refresh*(screenshot: var Screenshot) =
  let rect = captureRect(screenshot.hwnd)
  if rect.w != screenshot.width or rect.h != screenshot.height:
    screenshot.destroy()
    screenshot.x = rect.x
    screenshot.y = rect.y
    screenshot.width = rect.w
    screenshot.height = rect.h
    screenshot.grab()
  else:
    screenshot.x = rect.x
    screenshot.y = rect.y
    let hdcScreen = GetDC(0)
    defer: discard ReleaseDC(0, hdcScreen)
    discard BitBlt(
      screenshot.hdcMem, 0, 0, screenshot.width, screenshot.height,
      hdcScreen, screenshot.x, screenshot.y, SRCCOPY)

proc saveToBMP*(screenshot: Screenshot, filePath: string) =
  let pixelBytes = screenshot.width * screenshot.height * 4
  var fileHeader: BITMAPFILEHEADER
  fileHeader.bfType = 0x4D42 # "BM"
  fileHeader.bfOffBits = DWORD(sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER))
  fileHeader.bfSize = fileHeader.bfOffBits + DWORD(pixelBytes)

  var infoHeader: BITMAPINFOHEADER
  infoHeader.biSize = DWORD(sizeof(BITMAPINFOHEADER))
  infoHeader.biWidth = screenshot.width
  infoHeader.biHeight = -screenshot.height # top-down, matches our captured buffer
  infoHeader.biPlanes = 1
  infoHeader.biBitCount = 32
  infoHeader.biCompression = BI_RGB

  var f = open(filePath, fmWrite)
  defer: f.close
  discard f.writeBuffer(addr fileHeader, sizeof(BITMAPFILEHEADER))
  discard f.writeBuffer(addr infoHeader, sizeof(BITMAPINFOHEADER))
  discard f.writeBuffer(screenshot.data, pixelBytes)

proc saveToPPM*(screenshot: Screenshot, filePath: string) =
  var f = open(filePath, fmWrite)
  defer: f.close
  writeLine(f, "P6")
  writeLine(f, screenshot.width, " ", screenshot.height)
  writeLine(f, 255)
  for i in 0..<(screenshot.width * screenshot.height):
    f.write(screenshot.data[i * 4 + 2])
    f.write(screenshot.data[i * 4 + 1])
    f.write(screenshot.data[i * 4 + 0])
