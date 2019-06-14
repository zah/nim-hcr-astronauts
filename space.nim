import
  sdl2/sdl, sdl2/sdl_image as img,
  sdl2/sdl_ttf as ttf

import hotcodereloading


const
  Title = "SDL2 App"
  ScreenW = 640 # Window width
  ScreenH = 480 # Window height
  WindowFlags = 0
  RendererFlags = sdl.RendererAccelerated #or sdl.RendererPresentVsync


type
  App = ref AppObj
  AppObj = object
    window*: sdl.Window # Window pointer
    renderer*: sdl.Renderer # Rendering state pointer


  Image = ref ImageObj
  ImageObj = object of RootObj
    texture: sdl.Texture # Image texture
    w, h: int # Image dimensions


  FpsManager = ref FpsManagerObj
  FpsManagerObj = object
    counter, fps: int
    timer: sdl.TimerID


#########
# IMAGE #
#########

proc newImage(): Image = Image(texture: nil, w: 0, h: 0)
proc free(obj: Image) = sdl.destroyTexture(obj.texture)
proc w(obj: Image): int {.inline.} = return obj.w
proc h(obj: Image): int {.inline.} = return obj.h

# blend
proc blend(obj: Image): sdl.BlendMode =
  var blend: sdl.BlendMode
  if obj.texture.getTextureBlendMode(addr(blend)) == 0:
    return blend
  else:
    return sdl.BlendModeBlend

proc `blend=`(obj: Image, mode: sdl.BlendMode) {.inline.} =
  discard obj.texture.setTextureBlendMode(mode)

# alpha
proc alpha(obj: Image): int =
  var alpha: uint8
  if obj.texture.getTextureAlphaMod(addr(alpha)) == 0:
    return alpha
  else:
    return 255

proc `alpha=`(obj: Image, alpha: int) =
  discard obj.texture.setTextureAlphaMod(alpha.uint8)


# Load image from file
# Return true on success or false, if image can't be loaded
proc load(obj: Image, renderer: sdl.Renderer, file: string): bool =
  result = true
  # Load image to texture
  obj.texture = renderer.loadTexture(file)
  if obj.texture == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load image %s: %s",
                    file, img.getError())
    return false
  # Get image dimensions
  var w, h: cint
  if obj.texture.queryTexture(nil, nil, addr(w), addr(h)) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't get texture attributes: %s",
                    sdl.getError())
    sdl.destroyTexture(obj.texture)
    return false
  obj.w = w
  obj.h = h


# Render texture to screen
proc render(obj: Image, renderer: sdl.Renderer, x, y: int): bool =
  var rect = sdl.Rect(x: x, y: y, w: obj.w, h: obj.h)
  if renderer.renderCopy(obj.texture, nil, addr(rect)) == 0:
    return true
  else:
    return false


# Render transformed texture to screen
proc renderEx(obj: Image, renderer: sdl.Renderer, x, y: int,
            w = 0, h = 0, angle = 0.0, centerX = -1, centerY = -1,
            flip = sdl.FlipNone): bool =
  var
    rect = sdl.Rect(x: x, y: y, w: obj.w, h: obj.h)
    centerObj = sdl.Point(x: centerX, y: centerY)
    center: ptr sdl.Point = nil
  if w != 0: rect.w = w
  if h != 0: rect.h = h
  if not (centerX == -1 and centerY == -1): center = addr(centerObj)
  if renderer.renderCopyEx(obj.texture, nil, addr(rect),
                          angle, center, flip) == 0:
    return true
  else:
    return false


##############
# FPSMANAGER #
##############

# FPS timer
# param is FpsManager casted to pointer
proc fpsTimer(interval: uint32, param: pointer): uint32 {.cdecl.} =
  let obj = cast[FpsManager](param)
  obj.fps = obj.counter
  obj.counter = 0
  return interval


proc newFpsManager(): FpsManager = FpsManager(counter: 0, fps: 0, timer: 0)


proc free(obj: FpsManager) =
  discard sdl.removeTimer(obj.timer)
  obj.timer = 0


proc fps(obj: FpsManager): int {.inline.} = return obj.fps


proc start(obj: FpsManager) =
  obj.timer = sdl.addTimer(1000, fpsTimer, cast[pointer](obj))


proc count(obj: FpsManager) {.inline.} = inc(obj.counter)


##########
# COMMON #
##########

# Initialization sequence
proc init(app: App): bool =
  # Init SDL
  if sdl.init(sdl.InitVideo or sdl.InitTimer) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL: %s",
                    sdl.getError())
    return false

  # Init SDL_Image
  if img.init(img.InitPng) == 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL_Image: %s",
                    img.getError())

  # Init SDL_TTF
  if ttf.init() != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL_TTF: %s",
                    ttf.getError())

  # Create window
  app.window = sdl.createWindow(
    Title,
    sdl.WindowPosUndefined,
    sdl.WindowPosUndefined,
    ScreenW,
    ScreenH,
    WindowFlags)
  if app.window == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create window: %s",
                    sdl.getError())
    return false

  # Create renderer
  app.renderer = sdl.createRenderer(app.window, -1, RendererFlags)
  if app.renderer == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create renderer: %s",
                    sdl.getError())
    return false

  # Set draw color
  if app.renderer.setRenderDrawColor(0x00, 0x00, 0x00, 0xFF) != 0:
    sdl.logWarn(sdl.LogCategoryVideo,
                "Can't set draw color: %s",
                sdl.getError())
    return false

  sdl.logInfo(sdl.LogCategoryApplication, "SDL initialized successfully")
  return true


# Shutdown sequence
proc exit(app: App) =
  app.renderer.destroyRenderer()
  app.window.destroyWindow()
  ttf.quit()
  img.quit()
  sdl.logInfo(sdl.LogCategoryApplication, "SDL shutdown completed")
  sdl.quit()


# Render surface
proc render(renderer: sdl.Renderer,
          surface: sdl.Surface, x, y: int): bool =
  result = true
  var rect = sdl.Rect(x: x, y: y, w: surface.w, h: surface.h)
  # Convert to texture
  var texture = sdl.createTextureFromSurface(renderer, surface)
  if texture == nil:
    return false
  # Render texture
  if renderer.renderCopy(texture, nil, addr(rect)) != 0:
    result = false
  # Clean
  destroyTexture(texture)


# Event handling
# Return true on app shutdown request, otherwise return false
proc events(pressed: var seq[sdl.Keycode]): bool =
  result = false
  var e: sdl.Event
  if pressed.len > 0:
    pressed = @[]

  while sdl.pollEvent(addr(e)) != 0:

    # Quit requested
    if e.kind == sdl.Quit:
      return true

    # Key pressed
    elif e.kind == sdl.KeyDown:
      # Add pressed key to sequence
      pressed.add(e.key.keysym.sym)

      # Exit on Escape key press
      if e.key.keysym.sym == sdl.K_Escape:
        return true


########
# MAIN #
########

type
  Entity = object
    pos, speed: tuple [x, y: float] # Position and vector of movement
    angle, rotation: float # Angle and vector of rotation

const
  EntityCount = 10
  Speed = 10    # Speed in px/s
  Rotation = 10 # Rotation speed in degrees/s

# Load assets
var
  font: ttf.Font
  image = newImage()
  planet = newImage()
  planet_w = 400
  planet_h = 400
  entities: seq[Entity]


var
  app = App(window: nil, renderer: nil)
  pressed: seq[sdl.Keycode] = @[] # Pressed keys


# Init FPS manager
var
  fpsMgr = newFpsManager()
  delta = 0.0 # Time passed since last frame in seconds
  ticks: uint64 # Ticks counter
  freq = sdl.getPerformanceFrequency() # Get counter frequency
  fpsLimiter = 60 # FPS limit value
  delta_mul = 0.0



proc cleanup*() =
  # Free assets
  free(image)
  free(fpsMgr)
  ttf.closeFont(font)

  # Shutdown
  exit(app)


proc real_init*(): bool =
  if not init(app):
    return false
  

  font = ttf.openFont("fnt/FSEX300.ttf", 16)

  if font == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load font: %s",
                    ttf.getError())
    return false

  discard planet.load(app.renderer, "img/img2.png")

  if not image.load(app.renderer, "img/img1a.png"):
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load image: %s",
                    img.getError())

  # Init entities
  entities = @[]
  for i in 0..EntityCount:
    entities.add(Entity())
    entities[i].pos.x = i.float * 60
    entities[i].pos.y = 400
    entities[i].speed.x = (i mod EntityCount + 1).float * Speed
    entities[i].speed.y = (i mod EntityCount + 1).float * Speed
    entities[i].rotation = (i mod EntityCount + 1).float * Rotation


  fpsMgr.start()

  ticks = getPerformanceCounter()

  return true

proc main_loop*(): bool =

  # Clear screen with draw color
  discard app.renderer.setRenderDrawColor(0x00, 0x00, 0x00, 0xFF)
  if app.renderer.renderClear() != 0:
    sdl.logWarn(sdl.LogCategoryVideo,
                "Can't clear screen: %s",
                sdl.getError())

  # render planet
  discard planet.renderEx(app.renderer, 0, 0, planet_w, planet_h)

  # Render entities
  for i in 0..entities.high:
    if not image.renderEx(app.renderer,
                          entities[i].pos.x.int - image.w div 2,
                          entities[i].pos.y.int - image.h div 2,
                          angle = entities[i].angle):
      sdl.logWarn(sdl.LogCategoryVideo,
                  "Can't render image: %s",
                  sdl.getError())

  # HCR DEMO

  # var s = font.renderUTF8_Shaded("SORRY I HAVE NO IMAGINATION :|",
  #                                 sdl.Color(r: 0xFF, g: 0x00, b: 0x00),
  #                                 sdl.Color(r: 0x00, g: 0x00, b: 0x00))
  # discard app.renderer.render(s, 50, 50):
  # sdl.freeSurface(s)

  # Update renderer
  app.renderer.renderPresent()

  # Event handling
  let done = events(pressed)

  if K_q in pressed: fpsLimiter += 10
  if K_a in pressed: fpsLimiter -= 10
  if fpsLimiter < 10: fpsLimiter = 10

  # HCR DEMO

  planet_w.dec
  planet_h.dec

  # Count frame
  fpsMgr.count()

  # Limit FPS
  let spare = uint32(1000 / fpsLimiter) -
    1000'u32 * uint32((sdl.getPerformanceCounter() - ticks).float /
    freq.float)
  if spare > 0'u32:
    sdl.delay(spare)

  # Get frame duration
  delta = (sdl.getPerformanceCounter() - ticks).float / freq.float
  ticks = sdl.getPerformanceCounter()
  delta = delta * delta_mul

  # Update entities
  for i in 0..entities.high:
    entities[i].pos.x += entities[i].speed.x * delta
    entities[i].pos.y += entities[i].speed.y * delta
    entities[i].angle += entities[i].rotation * delta

    if entities[i].pos.x < 0:
      entities[i].pos.x = 0
      entities[i].speed.x = - entities[i].speed.x

    if entities[i].pos.x > ScreenW.float:
      entities[i].pos.x = ScreenW.float
      entities[i].speed.x = - entities[i].speed.x

    if entities[i].pos.y < 0:
      entities[i].pos.y = 0
      entities[i].speed.y = - entities[i].speed.y

    if entities[i].pos.y > ScreenH.float:
      entities[i].pos.y = ScreenH.float
      entities[i].speed.y = - entities[i].speed.y

    if entities[i].angle > 360:
      entities[i].angle -= 360

    if entities[i].angle < -360:
      entities[i].angle += 360
  
  return not done

afterCodeReload:

  delta_mul = 2
  
  entities = @[entities[0], entities[1], entities[2]]

  discard
