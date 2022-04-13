import
  std/[options, os, sequtils, strutils],
  x11/[xlib, x, xft, xatom, xinerama, xrender],
  types,
  atoms,
  log,
  pixie,
  regex

converter toXBool*(x: bool): XBool = x.XBool
converter toBool*(x: XBool): bool = x.bool

type
  Wm* = object
    dpy*: ptr Display
    root*: Window
    motionInfo*: Option[MotionInfo]
    currEv*: XEvent
    clients*: seq[Client]
    font*: ptr XftFont
    netAtoms*: array[NetAtom, Atom]
    ipcAtoms*: array[IpcAtom, Atom]
    config*: Config
    focused*: Option[uint]
    tags*: TagSet
    layout*: Layout
    noDecorList*: seq[Regex]

proc initWm*(): Wm =
  let dpy = XOpenDisplay nil

  if dpy == nil:
    quit 1

  log "Opened display"

  let root = XDefaultRootWindow dpy

  for button in [1'u8, 3]:
    # list from sxhkd (Mod2Mask NumLock, Mod3Mask ScrollLock, LockMask CapsLock).
    for mask in [
      uint32 Mod1Mask, Mod1Mask or Mod2Mask, Mod1Mask or LockMask,
      Mod1Mask or Mod3Mask, Mod1Mask or Mod2Mask or LockMask, Mod1Mask or
      LockMask or Mod3Mask, Mod1Mask or Mod2Mask or Mod3Mask, Mod1Mask or
      Mod2Mask or LockMask or Mod3Mask
      ]:
      discard dpy.XGrabButton(
        button,
        mask,
        root,
        true,
        ButtonPressMask or PointerMotionMask,
        GrabModeAsync,
        GrabModeAsync,
        None,
        None
      )

  discard dpy.XSelectInput(
    root,
    SubstructureRedirectMask or SubstructureNotifyMask or ButtonPressMask
  )

  let
    font = dpy.XftFontOpenName(XDefaultScreen dpy, "Noto Sans Mono:size=11")
    netAtoms = getNetAtoms dpy

  discard dpy.XChangeProperty(
    root,
    netAtoms[NetSupportingWMCheck],
    XaWindow,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr root),
    1
  )

  discard dpy.XChangeProperty(
    root,
    netAtoms[NetSupported],
    XaAtom,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr netAtoms),
    netAtoms.len.cint
  )

  let wmname = "worm".cstring
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetWMName],
    dpy.XInternAtom("UTF8_STRING", false),
    8,
    PropModeReplace,
    wmname,
    4
  )

  var numdesk = [9]
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetNumberOfDesktops],
    XaCardinal,
    32,
    PropModeReplace,
    cast[cstring](addr numdesk),
    1
  )

  numdesk = [0]
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetCurrentDesktop],
    XaCardinal,
    32,
    PropModeReplace,
    cast[cstring](addr numdesk),
    1
  )

  discard dpy.XChangeProperty(
    root,
    netAtoms[NetClientList],
    XaWindow,
    32,
    PropModeReplace,
    nil,
    0
  )

  discard XSetErrorHandler(
    proc(dpy: ptr Display; err: ptr XErrorEvent): cint {.cdecl.} = 0
  )

  discard dpy.XSync false

  discard dpy.XFlush

  # The default configuration is reasonably sane, and for now based on the
  # Iceberg colorscheme. It may be changed later; it's recommended for users to
  # write their own.
  Wm(
    dpy: dpy,
    root: root,
    motionInfo: none MotionInfo,
    font: font,
    netAtoms: netAtoms,
    ipcAtoms: getIpcAtoms dpy,
    config: Config(
      borderActivePixel: uint 0xFF7499CC,
      borderInactivePixel: uint 0xFF000000,
      borderWidth: 1,
      frameActivePixel: uint 0xFF161821,
      frameInactivePixel: uint 0xFF666666,
      frameHeight: 30,
      textActivePixel: uint 0xFFFFFFFF,
      textInactivePixel: uint 0xFF000000,
      textOffset: (x: uint 10, y: uint 20),
      gaps: 0,
      buttonSize: 14,
      struts: (top: uint 10, bottom: uint 40, left: uint 10, right: uint 10)
      ),
    tags: defaultTagSet(),
    layout: lyFloating,
    noDecorList: @[]
  )

func findClient*(
  self: var Wm;
  predicate: proc(client: Client): bool
  ): Option[(ptr Client, uint)] =

  for i, client in self.clients:
    if predicate client:
      return some((addr self.clients[i], uint i))

proc createBtnImg(c: Config, imgPath: string, framePixel: uint): Image =
  let btnSize = c.buttonSize.int
  result = newImage(btnSize, btnSize)

  let buttonColor = cast[array[3, uint8]](framePixel)

  result.fill(rgba(buttonColor[2], buttonColor[1], buttonColor[0], 255))

  let img = readImage(imgPath)
  result.draw(
    img,
    scale(vec2(btnSize / img.width, btnSize / img.height))
  )

proc getBGRXBitmap(im: Image): seq[ColorRGBX] =
  var ctx = newContext im
  # convert to BGRA
  result = ctx.image.data

  for i, color in result:
    let x = color
    # RGBX -> BGRX
    result[i].r = x.b
    result[i].b = x.r

proc XCreateImage(
  self: var Wm,
  imgPath: string,
  framePixel: uint,
  attr: XWindowAttributes
  ): PXImage =
  var screen = self.config.createBtnImg(imgPath, framePixel)

  var
    bitmap = screen.getBGRXBitmap()
    frameBuffer = addr bitmap[0]

  result = XCreateImage(
    self.dpy,
    attr.visual,
    attr.depth.cuint,
    ZPixmap,
    0,
    cast[cstring](frameBuffer),
    self.config.buttonSize.cuint,
    self.config.buttonSize.cuint,
    8,
    self.config.buttonSize.cint*4
  )

proc XPutImage(self: var Wm, img: PXImage, win: Window, gc: GC) =
  let btnSize = self.config.buttonSize.cuint
  discard self.dpy.XPutImage(win, gc, img, 0, 0, 0, 0, btnSize, btnSize)

proc renderTop*(self: var Wm; client: var Client) =
  var extent: XGlyphInfo
  self.dpy.XftTextExtentsUtf8(
    self.font,
    cast[ptr char](cstring client.title),
    cint client.title.len, addr extent
  )

  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)

  for win in [client.frame.title, client.frame.close, client.frame.maximize]:
    discard self.dpy.XClearWindow win

  var
    gcVal: XGCValues
    gc = self.dpy.XCreateGC(client.frame.close, 0, addr gcVal)

  # discard self.dpy.XSetForeground(gc, self.config.textActivePixel)
  let
    isFocused = self.focused.isSome and client == self.clients[self.focused.get]
    fp =
      if isFocused:
        self.config.frameActivePixel
      else:
        self.config.frameInactivePixel
    buttonState =
      if isFocused:
        bsActive
      else:
        bsInactive

  # draw the 3 'regions' of the titlebar; left, center, right
  var
    closeExists = false
    maximizeExists = false
    minimizeExists = false

  discard self.dpy.XUnmapWindow client.frame.close
  discard self.dpy.XUnmapWindow client.frame.maximize

  # load the image @ path into the frame top at offset (x, y)
  proc loadImage(path: string; x, y: uint): void =
    discard

  for i, part in self.config.frameParts.left:
    case part:
    of fpTitle:

      if not closeExists:
        discard self.dpy.XUnmapWindow client.frame.close

      if not maximizeExists:
        discard self.dpy.XUnmapWindow client.frame.maximize

      let
        buttonSize = self.config.buttonSize.cint
        buttonXOffset = self.config.buttonOffset.x.cint
        leftFrame0 = self.config.frameParts.left[0]

        offset =
          if i == 1 and leftFrame0 in {fpClose, fpMaximize, fpMinimize}:
            buttonSize + buttonXOffset
          elif i == 2:
            (buttonSize + buttonXOffset) * 2
          elif i == 3:
            (buttonSize + buttonXOffset) * 3
          else:
            0

      client.draw.XftDrawStringUtf8(
        addr client.color,
        self.font,
        self.config.textOffset.x.cint + offset,
        self.config.textOffset.y.cint,
        cast[ptr char](cstring client.title),
        client.title.len.cint
      )

    of fpClose:

      closeExists = true

      if not fileExists self.config.closePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.close

      let
        buttonSize = self.config.buttonSize.cint
        buttonXOffset = self.config.buttonOffset.x.cint
        buttonYOffset = self.config.buttonOffset.y.cint
        textXOffset = self.config.textOffset.x.cint
        leftFrame0 = self.config.frameParts.left[0]

        offset =
          if i == 1 and leftFrame0 == fpTitle:
            extent.width + textXOffset
          elif i == 1 and leftFrame0 in {fpMaximize, fpMinimize}:
            buttonSize + buttonXOffset
          elif i == 2 and (leftFrame0 == fpTitle or self.config.frameParts.left[1] == fpTitle):
            extent.width + textXOffset + 2*buttonXOffset + buttonSize
          elif i == 2: # no title
            2*(buttonSize + buttonXOffset)
          elif i == 3:
            extent.width + textXOffset + buttonXOffset*2 + buttonSize*2
          else:
            0

      discard self.dpy.XMoveWindow(
        client.frame.close,
        buttonXOffset + offset,
        buttonYOffset
      )

      let image = self.XCreateImage(self.config.closePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.close, gc)

    of fpMaximize:

      maximizeExists = true

      if not fileExists self.config.maximizePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.maximize

      let
        leftFrame0 = self.config.frameParts.left[0]
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        textXOffset = self.config.textOffset.x.cint
        buttonSize = self.config.buttonSize.cint

        offset =
          if i == 1 and leftFrame0 == fpTitle:
            extent.width.cint
          elif i == 1 and leftFrame0 in {fpClose, fpMinimize}:
            btnSize + btnXOffset
          elif i == 2 and (leftFrame0 == fpTitle or self.config.frameParts.left[1] == fpTitle):
            extent.width + textXOffset + btnXOffset + buttonSize
          elif i == 2: # no title
            2*(buttonSize + btnXOffset)
          elif i == 3:
            extent.width + textXOffset + btnXOffset*2 + buttonSize*2
          else:
            0

      discard self.dpy.XMoveWindow(
        client.frame.maximize,
        self.config.buttonOffset.x.cint + offset,
        self.config.buttonOffset.y.cint
      )

      let image = self.XCreateImage(self.config.maximizePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.maximize, gc)
    of fpMinimize: 
      minimizeExists = true

      if not fileExists self.config.minimizePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.minimize

      let
        leftFrame0 = self.config.frameParts.left[0]
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        textXOffset = self.config.textOffset.x.cint
        buttonSize = self.config.buttonSize.cint

        offset =
          if i == 1 and leftFrame0 == fpTitle:
            extent.width.cint + btnXOffset + textXOffset
          elif i == 1 and leftFrame0 in {fpClose, fpMaximize}:
            btnSize + btnXOffset
          elif i == 2 and (leftFrame0 == fpTitle or self.config.frameParts.left[1] == fpTitle):
            extent.width + textXOffset + btnXOffset + buttonSize
          elif i == 2: # no title
            2*(buttonSize + btnXOffset)
          elif i == 3:
            extent.width + textXOffset + btnXOffset*2 + buttonSize*2
          else:
            0

      discard self.dpy.XMoveWindow(
        client.frame.minimize,
        self.config.buttonOffset.x.cint + offset,
        self.config.buttonOffset.y.cint
      )

      let image = self.XCreateImage(self.config.minimizePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.minimize, gc)
  for i, part in self.config.frameParts.center:
    case part:
    of fpTitle:

      if not closeExists:
        discard self.dpy.XUnmapWindow client.frame.close

      let configButtonSize =
        if i == 2:
          self.config.buttonSize.cint
        else:
          0

      client.draw.XftDrawStringUtf8(
        addr client.color,
        self.font,
        ((attr.width div 2).cint - (extent.width.cint div 2)) + 
        configButtonSize + self.config.textOffset.x.cint,
        self.config.textOffset.y.cint,
        cast[ptr char](cstring client.title),
        client.title.len.cint
      )

    of fpClose:

      closeExists = true

      if not fileExists self.config.closePaths[buttonState]:
        continue

      let image = self.XCreateImage(self.config.closePaths[buttonState], fp, attr)

      let
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        textXOffset = self.config.textOffset.x.cint
        centerFrames = self.config.frameParts.center

      discard self.dpy.XMoveWindow(
        client.frame.close,
        (if i == 0: -btnXOffset else: btnXOffset) + (
          if (i == 1 and centerFrames[0] == fpTitle and centerFrames.len == 2):
            textXOffset + extent.width div 2
          elif (i == 1 and centerFrames[0] == fpTitle and
                centerFrames.len > 2 and centerFrames[1] == fpMaximize):
            -(extent.width div 2) - btnSize - btnXOffset - textXOffset
          elif i == 2 and centerFrames[0] == fpTitle:
            (extent.width div 2) + btnXOffset + textXOffset + btnSize
          elif i == 1 and centerFrames[0] == fpTitle:
            (extent.width div 2) + btnXOffset + textXOffset - btnSize
          elif (i == 1 and centerFrames.len >= 3 and
                centerFrames[0] == fpMaximize and centerFrames[2] == fpTitle):
                # meh
            -(extent.width div 2)
          elif i == 2 and centerFrames[1] == fpTitle:
            btnSize + extent.width div 2
          elif i == 1 and centerFrames[0] in {fpMaximize, fpMinimize}:
            btnSize - btnXOffset
          elif i == 2:
            # -btnSize
            btnSize * 2
          else:
            0
        ) + (attr.width div 2) - (
          if (i == 0 and centerFrames.len > 1 and
              centerFrames.find(fpTitle) != -1):
            self.config.buttonSize.cint + extent.width div 2
          else:
            0),
        self.config.buttonOffset.y.cint
      )

      discard self.dpy.XMapWindow client.frame.close

      self.XPutImage(image, client.frame.close, gc)

    of fpMaximize:

      maximizeExists = true

      if not fileExists self.config.maximizePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.maximize

      let
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        btnYOffset = self.config.buttonOffset.y.cint
        textXOffset = self.config.textOffset.x.cint
        centerFrames = self.config.frameParts.center

      # M;T;C
      discard self.dpy.XMoveWindow(
        client.frame.maximize,
        btnXOffset + (
          if i == 1 and centerFrames[0] == fpTitle:
            textXOffset + extent.width div 2
          elif i == 1 and centerFrames[0] in {fpClose, fpMinimize}:
            btnSize - btnXOffset
          elif i == 2 and centerFrames[1] == fpTitle:
            extent.width div 2
          elif i == 2 and (centerFrames[0] == fpTitle or centerFrames[1] == fpTitle):
            extent.width div 2 + btnSize + btnXOffset
          elif i == 2:
            btnSize * 2
          elif i == 0 and centerFrames.len > 2 and (centerFrames[0] == fpTitle or centerFrames[1] == fpTitle):
            # meh
            -(extent.width div 2) - btnXOffset
          elif i == 0:
            -btnXOffset * 2
          else:
            0
        ) + (attr.width div 2),
        btnYOffset
      )

      let image = self.XCreateImage(self.config.maximizePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.maximize, gc)
    of fpMinimize:
      minimizeExists = true

      if not fileExists self.config.minimizePaths[buttonState]:
        continue

      let image = self.XCreateImage(self.config.minimizePaths[buttonState], fp, attr)

      let
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        textXOffset = self.config.textOffset.x.cint
        centerFrames = self.config.frameParts.center

      discard self.dpy.XMoveWindow(
        client.frame.minimize,
        (if i == 0: -btnXOffset else: btnXOffset) + (
          if (i == 1 and centerFrames[0] == fpTitle and centerFrames.len == 2):
            textXOffset + extent.width div 2
          elif (i == 1 and centerFrames[0] == fpTitle and
                centerFrames.len > 2 and centerFrames[1] in {fpClose, fpMaximize}):
            -(extent.width div 2) - btnSize - btnXOffset - textXOffset
          elif i == 1 and centerFrames[0] == fpTitle:
            (extent.width div 2) + btnXOffset + textXOffset - btnSize
          elif (i == 1 and centerFrames.len >= 3 and
                centerFrames[0] in {fpMaximize, fpClose} and centerFrames[2] == fpTitle):
                # meh
            -(extent.width div 2)
          elif i == 2 and (centerFrames[1] == fpTitle or centerFrames[0] == fpTitle):
            (extent.width div 2) + btnXOffset + textXOffset + btnSize
          elif i == 2:
            # ez
            echo "HIT"
            btnSize * 2
          elif (i == 1 and centerFrames.len >= 3 and (centerFrames[0] == fpTitle or centerFrames[1] == fpTitle)):
            -(extent.width div 2) + btnSize
          elif i == 1 and centerFrames[0] in {fpMaximize, fpClose}:
            btnSize - btnXOffset
          else:
            0
        ) + (attr.width div 2) - (
          if (i == 0 and centerFrames.len > 1 and
              centerFrames.find(fpTitle) != -1):
            self.config.buttonSize.cint + extent.width div 2
          else:
            0),
        self.config.buttonOffset.y.cint
      )

      discard self.dpy.XMapWindow client.frame.minimize

      self.XPutImage(image, client.frame.minimize, gc)

  for i, part in self.config.frameParts.right:

    case part:
    of fpTitle:

      if not closeExists:
        discard self.dpy.XUnmapWindow client.frame.close

      let
        rightFrames = self.config.frameParts.right
        textXOffset = self.config.textOffset.x.cint
        btnXOffset = self.config.buttonOffset.x.cint
        btnSize = self.config.buttonSize.cint

      client.draw.XftDrawStringUtf8(
        addr client.color,
        self.font,
        (
          if (rightFrames.len == 1 or (rightFrames.len == 2 and i == 1 and
                  rightFrames[0] in {fpClose, fpMaximize, fpMinimize})):
            attr.width.cint - (extent.width.cint + textXOffset)
          elif (rightFrames.len == 2 and i == 0 and
                rightFrames[1] in {fpClose, fpMaximize, fpMinimize}):
            attr.width.cint - extent.width.cint - textXOffset - btnXOffset - btnSize
          elif (i == 1 and rightFrames.len == 3 and
                rightFrames[0] in {fpClose, fpMaximize, fpMinimize}):
            attr.width.cint - (extent.width.cint + btnSize + btnXOffset)
          elif i == 2:
            attr.width.cint - extent.width.cint - textXOffset
          elif i == 0 and rightFrames.len == 3:
            attr.width.cint - extent.width.cint - btnSize * 2 - btnXOffset * 3
          else:
            0
        ),
        self.config.textOffset.y.cint,
        cast[ptr char](cstring client.title),
        client.title.len.cint
      )

    of fpClose:

      closeExists = true

      if not fileExists self.config.closePaths[buttonState]:
        continue

      let image = self.XCreateImage(self.config.closePaths[buttonState], fp, attr)

      let
        btnXOffset = self.config.buttonOffset.x.cint
        btnYOffset = self.config.buttonOffset.y.cint
        textXOffset = self.config.textOffset.x.cint
        btnSize = self.config.buttonSize.cint
        rightFrames = self.config.frameParts.right

      discard self.dpy.XMoveWindow(
        client.frame.close,
        (if i == 0: - btnXOffset else: btnXOffset) +
          (
            if i == 1 and rightFrames.len == 2 and fpTitle notin rightFrames:
              -btnXOffset*2
            elif i == 1:
              -btnSize - btnXOffset*3
            elif i == 0 and rightFrames.len == 2 and rightFrames[1] == fpTitle:
              - extent.width - btnSize
            elif (i == 0 and rightFrames.len == 2 and rightFrames[1] in {fpMinimize, fpMaximize}):
              - btnSize - btnXOffset
            elif i == 0 and rightFrames.len == 3 and fpTitle in rightFrames:
              - btnSize - textXOffset - btnXOffset - extent.width
            elif i == 0 and rightFrames.len == 3:
              -btnSize * 2 - btnXOffset*2
            elif i == 2:
              - btnXOffset*2
            else:
              0
          ) + attr.width - btnSize - (
            if i == 0 and self.config.frameParts.center.len > 1:
              btnSize + extent.width div 2
            else:
              0
          ),
          btnYOffset
      )

      discard self.dpy.XMapWindow client.frame.close

      self.XPutImage(image, client.frame.close, gc)

    of fpMaximize:

      maximizeExists = true

      if not fileExists self.config.maximizePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.maximize

      let
        rightFrames = self.config.frameParts.right
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint
        textOffset = self.config.textOffset.x.cint

        offset =
          if i == 1 and rightFrames[0] == fpTitle and rightFrames.len == 3:
            - btnSize * 2 - btnXOffset
          elif i == 1 and rightFrames[0] == fpTitle:
            - btnSize
          elif (i == 1 and rightFrames[0] in {fpClose, fpMinimize} and 
                rightFrames.len == 3 and rightFrames[2] == fpTitle):
            - extent.width - btnXOffset * 2 - textOffset
          elif i == 1 and fpTitle notin rightFrames and rightFrames.len == 3:
            - btnSize - btnXOffset*3
          elif i == 1 and rightFrames[0] in {fpClose, fpMinimize}:
            - btnXOffset * 3
          elif i == 2:
            - btnXOffset * 2
          elif i == 0 and rightFrames.len == 2 and rightFrames[1] in {fpClose, fpMinimize}:
            - btnXOffset * 3 - btnSize
          elif i == 0 and rightFrames.len > 2 and rightFrames[1] in {fpClose, fpMinimize} and fpTitle in rightFrames:
            - btnXOffset * 3 - btnSize - extent.width
          elif i == 0 and rightFrames.len >= 2 and rightFrames[1] == fpTitle:
            - extent.width - btnXOffset*2 - btnSize
          elif i == 0 and rightFrames.len == 1:
            - btnXOffset * 2
          elif i == 0 and rightFrames.len == 3:
            - btnSize * 2 - btnXOffset * 4
          else:
            0

      discard self.dpy.XMoveWindow(
        client.frame.maximize,
        self.config.buttonOffset.x.cint + offset + attr.width - 
        self.config.buttonSize.cint,
        self.config.buttonOffset.y.cint
      )

      let image = self.XCreateImage(self.config.maximizePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.maximize, gc)
    of fpMinimize:
      minimizeExists = true

      if not fileExists self.config.minimizePaths[buttonState]:
        continue

      discard self.dpy.XMapWindow client.frame.minimize

      let
        rightFrames = self.config.frameParts.right
        btnSize = self.config.buttonSize.cint
        btnXOffset = self.config.buttonOffset.x.cint

        offset =
          if i == 1 and rightFrames[0] == fpTitle and rightFrames.len == 3:
            - btnSize * 2 - btnXOffset
          elif i == 1 and rightFrames[0] == fpTitle:
            - btnSize
          elif (i == 1 and rightFrames[0] in {fpClose, fpMaximize} and 
                rightFrames.len == 3 and rightFrames[2] == fpTitle):
            - extent.width - btnXOffset * 2
          elif i == 1 and rightFrames.len == 3:
            - btnXOffset*3 - btnSize
          elif i == 1:
            -btnXOffset*2
          elif i == 2:
            - btnXOffset * 2
          elif i == 0 and rightFrames.len == 2 and rightFrames[1] in {fpClose, fpMaximize}:
            - btnXOffset * 4 - btnSize
          elif i == 0 and rightFrames.len > 2 and rightFrames[1] in {fpClose, fpMaximize} and fpTitle in rightFrames:
            - btnXOffset * 3 - btnSize - extent.width
          elif i == 0 and rightFrames.len >= 2 and rightFrames[1] == fpTitle:
            - extent.width - btnXOffset*2 - btnSize
          elif i == 0 and rightFrames.len == 1:
            - btnXOffset * 2
          elif i == 0 and rightFrames.len == 3:
            # we might be doing the plain old I;M;C that everyone loves lol
            (- btnSize * 2) - (btnXOffset * 4)
          else:
            0

      discard self.dpy.XMoveWindow(
        client.frame.minimize,
        self.config.buttonOffset.x.cint + offset + attr.width - 
        self.config.buttonSize.cint,
        self.config.buttonOffset.y.cint
      )

      let image = self.XCreateImage(self.config.minimizePaths[buttonState], fp, attr)

      self.XPutImage(image, client.frame.minimize, gc)


proc tileWindows*(self: var Wm) =

  log "Tiling windows"

  var
    clientLen: uint = 0
    master: ptr Client = nil

  let struts = self.config.struts

  for i, client in self.clients:
    if client.fullscreen:
      return # causes issues

    if client.tags == self.tags and not client.floating:
    # We only care about clients on the current tag.
      if master == nil: 
      # This must be the first client on the tag, otherwise master would not be 
      # nil; therefore, we promote it to master.
        master = addr self.clients[i]
      inc clientLen

  if master == nil:
    return

  if clientLen == 0:
    return # we got nothing to tile.

  var
    scrNo: cint
    scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
      self.dpy.XineramaQueryScreens(addr scrNo)
    )

  # echo cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1)
  let masterWidth =
    if clientLen == 1:
      uint scrInfo[0].width - struts.left.cint -
      struts.right.cint - self.config.borderWidth.cint*2
    else:
      uint scrInfo[0].width shr 1 - struts.left.cint -
      self.config.borderWidth.cint*2

  log $masterWidth

  let h = (
    scrInfo[0].height - struts.top.int16 - struts.bottom.int16 -
    self.config.borderWidth.cint*2
  ).cuint
  discard self.dpy.XMoveResizeWindow(
    master.frame.window,
    struts.left.cint,
    struts.top.cint,
    masterWidth.cuint,
    h
  )

  discard self.dpy.XResizeWindow(
    master.window,
    masterWidth.cuint,
    (scrInfo[0].height - struts.top.cint - struts.bottom.cint -
    master.frameHeight.cint - self.config.borderWidth.cint*2).cuint
  )

  for win in [master.frame.title, master.frame.top]:
    discard self.dpy.XResizeWindow(
      win,
      masterWidth.cuint,
      master.frameHeight.cuint
    )

  self.renderTop master[]

  # discard self.dpy.XMoveResizeWindow(master.frame.window, cint self.config.struts.left, cint self.config.struts.top, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth * 2) - self.config.gaps*2 - int16 self.config.struts.right, cuint scrInfo[0].height - int16(self.config.borderWidth * 2) - int16(self.config.struts.top) - int16(self.config.struts.bottom)) # bring the master window up to cover half the screen
  # discard self.dpy.XResizeWindow(master.window, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) - self.config.gaps*2 - int16 self.config.struts.right, cuint scrInfo[0].height - int16(self.config.borderWidth*2) - int16(self.config.frameHeight) - int16(self.config.struts.top) - int16(self.config.struts.bottom)) # bring the master window up to cover half the screen

  var irrevelantLen: uint = 0
  for i, client in self.clients:
    if client.tags != self.tags or client == master[] or client.floating:
      inc irrevelantLen
      continue

    if clientLen == 2:
      discard self.dpy.XMoveWindow(
        client.frame.window,
        (scrInfo[0].width shr 1 + self.config.gaps).cint,
        struts.top.cint
      )

      let w =
        cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) -
        int16(self.config.borderWidth*2) -
        self.config.gaps - self.config.struts.right.cint

      discard self.dpy.XResizeWindow(
        client.frame.top,
        w,
        self.config.frameHeight.cuint
      )

      discard self.dpy.XResizeWindow(
        client.frame.title,
        w,
        self.config.frameHeight.cuint
      )

      discard self.dpy.XResizeWindow(
        client.window,
        w,
        (scrInfo[0].height - struts.top.cint - struts.bottom.cint -
        client.frameHeight.cint - self.config.borderWidth.cint*2).cuint
      )

    else:
      # How many windows are there in the stack? We must subtract 1 to ignore 
      # the master window; which we iterate over too.
      let stackElem = i - int irrevelantLen - 1

      let yGap =
        if stackElem != 0:
          self.config.gaps
        else:
          0

      # let subStrut = if stackElem = clientLen
      # XXX: the if stackElem == 1: 0 else: self.config.gaps is a huge hack
      # and also incorrect behavior; while usually un-noticeable it makes the 
      # top window in the stack bigger by the gaps. Fix this!!
      let w = (
        scrInfo[0].width shr (if clientLen == 1: 0 else: 1) -
        self.config.borderWidth.int16 * 2 - self.config.gaps - struts.right.cint
      ).cuint

      discard self.dpy.XResizeWindow(
        client.frame.top,
        w,
        self.config.frameHeight.cuint
      )

      discard self.dpy.XResizeWindow(
        client.frame.title,
        w,
        self.config.frameHeight.cuint
      ).cint

      var h = (
        ((scrInfo[0].height.float - struts.bottom.float - struts.top.float) *
         ((i - irrevelantLen.int) / clientLen.int - 1)).cint + struts.top.cint +
         (if stackElem == 1: 0 else: self.config.gaps.cint)
      )

      discard self.dpy.XMoveWindow(
        client.frame.window,
        (scrInfo[0].width shr 1 + yGap).cint,
        h
      )

      var h2 = (
        ((scrInfo[0].height - struts.bottom.cint - struts.top.cint) div
         (clientLen - 1).int16) - self.config.borderWidth.int16*2 -
         client.frameHeight.int16 - (if stackElem == 1: 0 else: self.config.gaps)
      ).cuint

      discard self.dpy.XResizeWindow(
        client.window,
        w,
        h2
      )
      # the number of windows on the stack is i (the current client) minus the 
      # master window minus any irrevelant windows
      # discard self.dpy.XMoveResizeWindow(client.frame.window, cint scrInfo[0].width shr 1, cint(float(scrInfo[0].height) * ((i - int irrevelantLen) / int clientLen - 1)) + cint self.config.gaps, cuint scrInfo[0].width shr 1 - int16(self.config.borderWidth * 2) - self.config.gaps, cuint (scrInfo[0].height div int16(clientLen - 1)) - int16(self.config.struts.bottom) - int16(self.config.borderWidth * 2) - self.config.gaps) # bring the master window up to cover half the screen
      # discard self.dpy.XResizeWindow(client.window, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) - self.config.gaps, cuint (scrInfo[0].height div int16(clientLen - 1)) - int16(self.config.struts.bottom) - int16(self.config.borderWidth*2) - int16(self.config.frameHeight) - self.config.gaps) # bring the master window up to cover half the screen

    self.renderTop self.clients[i]

    discard self.dpy.XSync false

    discard self.dpy.XFlush

proc minimizeClient*(
  self: var Wm;
  client: var Client
) =

  if not client.minimized:
    discard self.dpy.XUnmapWindow(client.frame.window)
    client.minimized = true
  else:
    client.minimized = false
    discard self.dpy.XMapWindow(client.frame.window)

proc maximizeClient*(
  self: var Wm;
  client: var Client,
  force = false,
  forceun = false
) =

  if (not force and client.maximized) or (force and forceun):
    if client.beforeGeomMax.isNone:
      return

    let geom = get client.beforeGeomMax

    client.maximized = false

    discard self.dpy.XMoveResizeWindow(
      client.frame.window,
      geom.x.cint,
      geom.y.cint,
      geom.width.cuint,
      geom.height.cuint
    )

    discard self.dpy.XMoveResizeWindow(
      client.window,
      0,
      cint self.config.frameHeight.cint,
      cuint geom.width.cuint,
      (geom.height - self.config.frameHeight).cuint
    )

    discard self.dpy.XChangeProperty(
      client.window,
      self.netAtoms[NetWMState],
      XaAtom,
      32,
      PropModeReplace,
      cast[cstring]([]),
      0
    )

    self.renderTop client
    return

  client.maximized = true

  # maximize the provided client
  var
    scrNo: cint
    scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
      self.dpy.XineramaQueryScreens(addr scrNo)
    )

  if scrInfo == nil:
    return

  # where the hell is our window at
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)

  client.beforeGeomMax = some Geometry(
    x: attr.x,
    y: attr.y,
    width: attr.width.uint,
    height: attr.height.uint
  )

  var
    x: int
    y: int
    width: uint
    height: uint

  if scrNo == 1:
    # 1st monitor, cuz only one
    x = 0
    y = 0
    width = scrInfo[0].width.uint
    height = scrInfo[0].height.uint
  else:
    var
      cumulWidth = 0
      cumulHeight = 0

    for i in countup(0, scrNo - 1):
      cumulWidth += scrInfo[i].width
      cumulHeight += scrInfo[i].height

      if attr.x <= cumulWidth - attr.width:
        x = scrInfo[i].xOrg
        y = scrInfo[i].yOrg
        width = scrInfo[i].width.uint
        height = scrInfo[i].height.uint

  let strut = self.config.struts

  discard self.dpy.XMoveWindow(
    client.frame.window,
    (strut.left + x.uint).cint,
    (strut.top + y.uint).cint
  )

  let masterWidth = (
    scrInfo[0].width - strut.left.cint - strut.right.cint -
    self.config.borderWidth.cint*2
  ).uint
  discard self.dpy.XResizeWindow(
    client.frame.window,
    masterWidth.cuint,
    (height - strut.top - strut.bottom - self.config.borderWidth.cuint*2).cuint
  )

  discard self.dpy.XResizeWindow(
    client.window,
    cuint masterWidth,
    cuint(
      height - strut.top - strut.bottom -
      client.frameHeight - self.config.borderWidth.cuint*2
    )
  )

  for win in [client.frame.top, client.frame.title]:
    discard self.dpy.XResizeWindow(
      win,
      masterWidth.cuint,
      self.config.frameHeight.cuint
    )

  var states = [NetWMStateMaximizedHorz, NetWMStateMaximizedVert]

  discard self.dpy.XChangeProperty(
    client.window,
    self.netAtoms[NetWMState],
    XaAtom,
    32,
    PropModeReplace,
    cast[cstring](addr states),
    0
  )

  discard self.dpy.XSync false

  discard self.dpy.XFlush

  self.renderTop client

proc updateClientList*(self: Wm) =
  let wins = self.clients.mapIt(it.window)

  if wins.len == 0:
    return

  discard self.dpy.XChangeProperty(
    self.root,
    self.netAtoms[NetClientList],
    XaWindow,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr wins[0]),
    wins.len.cint
  )

proc updateTagState*(self: Wm) =
  for client in self.clients:
    for i, tag in client.tags:
      if self.tags[i] and tag:
        discard self.dpy.XMapWindow client.frame.window
        break
      discard self.dpy.XUnmapWindow client.frame.window

proc raiseClient*(self: var Wm, client: var Client) =
  for locClient in self.clients.mitems:
    if locClient != client:
      discard self.dpy.XSetWindowBorder(locClient.frame.window,
          self.config.borderInactivePixel)
      var attr: XWindowAttributes
      discard self.dpy.XGetWindowAttributes(locClient.window, addr attr)
      var color: XftColor
      discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring(
          "#" & self.config.textInactivePixel.toHex 6), addr color)
      locClient.color = color
      for win in [
        locClient.frame.window,
        locClient.frame.top,
        locClient.frame.title,
        locClient.frame.close,
        locClient.frame.maximize
      ]:
        discard self.dpy.XSetWindowBackground(win, self.config.frameInactivePixel)
      self.renderTop locClient
  discard self.dpy.XSetWindowBorder(client.frame.window,
      self.config.borderActivePixel)
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(client.window, addr attr)
  var color: XftColor
  discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring(
      "#" & self.config.textActivePixel.toHex 6), addr color)
  client.color = color
  for win in [
    client.frame.window,
    client.frame.top,
    client.frame.title,
    client.frame.close,
    client.frame.maximize
  ]:
    discard self.dpy.XSetWindowBackground(win, self.config.frameActivePixel)
  self.renderTop client
  discard self.dpy.XSync false
  discard self.dpy.XFlush
