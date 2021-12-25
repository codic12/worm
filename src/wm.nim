import std/[options, os, osproc]
import x11/[xlib, x, xft, xatom, xinerama, xrender]
import types
import atoms
import log
import pixie
# import events/configurerequest

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

# event handlers
# proc handleButtonPress(self: var Wm; ev: XButtonEvent): void
# proc handleButtonRelease(self: var Wm; ev: XButtonEvent): void
# proc handleMotionNotify(self: var Wm; ev: XMotionEvent): void
# proc handleMapRequest(self: var Wm; ev: XMapRequestEvent): void
# proc handleConfigureRequest(self: var Wm; ev: XConfigureRequestEvent): void
# proc handleUnmapNotify(self: var Wm; ev: XUnmapEvent): void
# proc handleDestroyNotify(self: var Wm; ev: XDestroyWindowEvent): void
# proc handleClientMessage(self: var Wm; ev: XClientMessageEvent): void
# proc handleConfigureNotify(self: var Wm; ev: XConfigureEvent): void
# proc handleExpose(self: var Wm; ev: XExposeEvent): void
# proc handlePropertyNotify(self: var Wm; ev: XPropertyEvent): void
# others
proc newWm*: Wm
proc tileWindows*(self: var Wm): void
proc renderTop*(self: var Wm; client: var Client): void
# proc maximizeClient(self: var Wm; client: var Client): void
proc eventLoop*(self: var Wm): void
proc dispatchEvent*(self: var Wm; ev: XEvent): void
# func findClient(self: var Wm; predicate: proc(client: Client): bool): Option[(
#     ptr Client, uint)]
# proc updateClientList(self: Wm): void
# proc updateTagState(self: Wm): void
import events/configurerequest

proc newWm*: Wm =
  let dpy = XOpenDisplay nil
  if dpy == nil: quit 1
  log "Opened display"
  let root = XDefaultRootWindow dpy
  for button in [1'u8, 3]:
    # list from sxhkd (Mod2Mask NumLock, Mod3Mask ScrollLock, LockMask CapsLock).
    for mask in [uint32 Mod1Mask, Mod1Mask or Mod2Mask, Mod1Mask or LockMask,
        Mod1Mask or Mod3Mask, Mod1Mask or Mod2Mask or LockMask, Mod1Mask or
        LockMask or Mod3Mask, Mod1Mask or Mod2Mask or Mod3Mask, Mod1Mask or
        Mod2Mask or LockMask or Mod3Mask]:
      discard dpy.XGrabButton(button, mask, root, true, ButtonPressMask or
        PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None)
  discard dpy.XSelectInput(root, SubstructureRedirectMask or SubstructureNotifyMask or ButtonPressMask)
  let font = dpy.XftFontOpenName(XDefaultScreen dpy, "Noto Sans Mono:size=11")
  let netAtoms = getNetAtoms dpy
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
  discard XSetErrorHandler proc(dpy: ptr Display;
      err: ptr XErrorEvent): cint {.cdecl.} = 0
  discard dpy.XSync false
  discard dpy.XFlush
  Wm(dpy: dpy, root: root, motionInfo: none MotionInfo, font: font,
      netAtoms: netAtoms, ipcAtoms: getIpcAtoms dpy, config: Config(
          borderActivePixel: 0x7499CC, borderInactivePixel: 0x000000,
          borderWidth: 1,
          frameActivePixel: 0x161821, frameInactivePixel: 0x666666, frameHeight: 30,
          textPixel: 0xffffff, textOffset: (x: uint 10, y: uint 20), gaps: 0, buttonSize: 14,
              struts: (top: uint 10, bottom: uint 40, left: uint 10,
              right: uint 10)), tags: defaultTagSet(),
              layout: lyFloating) # The default configuration is reasonably sane, and for now based on the Iceberg colorscheme. It may be changed later; it's recommended for users to write their own.

proc tileWindows*(self: var Wm): void =
  log "Tiling windows"
  var clientLen: uint = 0
  var master: ptr Client = nil
  for i, client in self.clients:
    if client.fullscreen: return # causes issues
    if client.tags == self.tags and not client.floating: # We only care about clients on the current tag.
      if master == nil: # This must be the first client on the tag, otherwise master would not be nil; therefore, we promote it to master.
        master = addr self.clients[i]
      inc clientLen
  if master == nil: return
  if clientLen == 0: return # we got nothing to tile.
  var scrNo: cint
  var scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
      self.dpy.XineramaQueryScreens(addr scrNo))
  # echo cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1)
  let masterWidth = if clientLen == 1:
    uint scrInfo[0].width - self.config.struts.left.cint -
        self.config.struts.right.cint - cint self.config.borderWidth*2
  else:
    uint scrInfo[0].width shr 1 - self.config.struts.left.cint -
        cint self.config.borderWidth*2
  log $masterWidth
  discard self.dpy.XMoveResizeWindow(master.frame.window,
      cint self.config.struts.left, cint self.config.struts.top,
      cuint masterWidth, cuint scrInfo[0].height -
      self.config.struts.top.int16 - self.config.struts.bottom.int16 -
      cint self.config.borderWidth*2)
  discard self.dpy.XResizeWindow(master.window, cuint masterWidth,
      cuint scrInfo[0].height - self.config.struts.top.cint -
      self.config.struts.bottom.cint - self.config.frameHeight.cint -
      cint self.config.borderWidth*2)
  self.renderTop master[]
  # discard self.dpy.XMoveResizeWindow(master.frame.window, cint self.config.struts.left, cint self.config.struts.top, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth * 2) - self.config.gaps*2 - int16 self.config.struts.right, cuint scrInfo[0].height - int16(self.config.borderWidth * 2) - int16(self.config.struts.top) - int16(self.config.struts.bottom)) # bring the master window up to cover half the screen
  # discard self.dpy.XResizeWindow(master.window, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) - self.config.gaps*2 - int16 self.config.struts.right, cuint scrInfo[0].height - int16(self.config.borderWidth*2) - int16(self.config.frameHeight) - int16(self.config.struts.top) - int16(self.config.struts.bottom)) # bring the master window up to cover half the screen
  var irrevelantLen: uint = 0
  for i, client in self.clients:
    if client.tags != self.tags or client == master[] or client.floating:
      inc irrevelantLen
      continue
    if clientLen == 2:
      discard self.dpy.XMoveWindow(client.frame.window, cint scrInfo[
          0].width shr 1 + self.config.gaps, cint self.config.struts.top)
      discard self.dpy.XResizeWindow(client.window, cuint scrInfo[0].width shr (
          if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) -
          self.config.gaps - self.config.struts.right.cint, cuint scrInfo[
          0].height - self.config.struts.top.cint -
          self.config.struts.bottom.cint - self.config.frameHeight.cint -
          cint self.config.borderWidth*2)
    else:
      let stackElem = i - int irrevelantLen -
          1 # How many windows are there in the stack? We must subtract 1 to ignore the master window; which we iterate over too.
      let yGap = if stackElem != 0:
        self.config.gaps
      else:
        0
      # let subStrut = if stackElem = clientLen
      # XXX: the if stackElem == 1: 0 else: self.config.gaps is a huge hack
      # and also incorrect behavior; while usually un-noticeable it makes the top window in the stack bigger by the gaps. Fix this!!
      discard self.dpy.XMoveWindow(client.frame.window, cint scrInfo[
          0].width shr 1 + yGap, cint((float(scrInfo[0].height) - (
          self.config.struts.bottom.float + self.config.struts.top.float)) * ((
          i - int irrevelantLen) / int clientLen - 1)) +
          self.config.struts.top.cint + (if stackElem ==
          1: 0 else: self.config.gaps.cint))
      discard self.dpy.XResizeWindow(client.window, cuint scrInfo[0].width shr (
          if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) -
          self.config.gaps - self.config.struts.right.cint, cuint ((scrInfo[
          0].height - self.config.struts.bottom.cint -
          self.config.struts.top.cint) div int16(clientLen - 1)) - int16(
          self.config.borderWidth*2) - int16(self.config.frameHeight) - (
          if stackElem == 1: 0 else: self.config.gaps))
      # the number of windows on the stack is i (the current client) minus the master window minus any irrevelant windows
      # discard self.dpy.XMoveResizeWindow(client.frame.window, cint scrInfo[0].width shr 1, cint(float(scrInfo[0].height) * ((i - int irrevelantLen) / int clientLen - 1)) + cint self.config.gaps, cuint scrInfo[0].width shr 1 - int16(self.config.borderWidth * 2) - self.config.gaps, cuint (scrInfo[0].height div int16(clientLen - 1)) - int16(self.config.struts.bottom) - int16(self.config.borderWidth * 2) - self.config.gaps) # bring the master window up to cover half the screen
      # discard self.dpy.XResizeWindow(client.window, cuint scrInfo[0].width shr (if clientLen == 1: 0 else: 1) - int16(self.config.borderWidth*2) - self.config.gaps, cuint (scrInfo[0].height div int16(clientLen - 1)) - int16(self.config.struts.bottom) - int16(self.config.borderWidth*2) - int16(self.config.frameHeight) - self.config.gaps) # bring the master window up to cover half the screen
    self.renderTop self.clients[i]
    discard self.dpy.XSync false
    discard self.dpy.XFlush

proc renderTop*(self: var Wm; client: var Client): void =
  var extent: XGlyphInfo
  self.dpy.XftTextExtentsUtf8(self.font, cast[ptr char](cstring client.title),
      cint client.title.len, addr extent)
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)
  for win in [client.frame.title, client.frame.close]: discard self.dpy.XClearWindow win
  var gc: GC
  var gcVal: XGCValues
  gc = self.dpy.XCreateGC(client.frame.close, 0, addr gcVal)
  discard self.dpy.XSetForeground(gc, self.config.textPixel)
  let fp = if self.focused.isSome and client == self.clients[self.focused.get]: self.config.frameActivePixel else: self.config.frameInactivePixel
  discard self.dpy.XSetBackground(gc, fp)
  var
    bw: cuint
    bh: cuint
    hx: cint
    hy: cint
    bitmap: PixMap
  discard self.dpy.XReadBitmapFile(client.frame.close, "icon.bmp", addr bw,
      addr bh, addr bitmap, addr hx, addr hy)
  # draw the 3 'regions' of the titlebar; left, center, right
  var closeExists = false
  var maximizeExists = false
  discard self.dpy.XUnmapWindow client.frame.close
  discard self.dpy.XUnmapWindow client.frame.maximize
  # load the image @ path into the frame top at offset (x, y)
  proc loadImage(path: string; x, y: uint): void = 
    discard
  for i, part in self.config.frameParts.left:
    case part:
    of fpTitle:
      if not closeExists: discard self.dpy.XUnmapWindow client.frame.close
      if not maximizeExists: discard self.dpy.XUnmapWindow client.frame.maximize
      client.draw.XftDrawStringUtf8(addr client.color, self.font,
        self.config.textOffset.x.cint + (
          if i == 1 and self.config.frameParts.left[0] in {fpClose, fpMaximize}:
            self.config.buttonSize.cint + self.config.buttonOffset.x.cint
          elif i == 2:
            self.config.buttonSize.cint*2 + self.config.buttonOffset.x.cint*2
          else: 0),
            cint self.config.textOffset.y, cast[
          ptr char](cstring client.title), cint client.title.len)
    of fpClose:
      closeExists = true
      if not fileExists self.config.closePath: continue
      discard self.dpy.XMapWindow client.frame.close
      discard self.dpy.XMoveWindow(client.frame.close,
          self.config.buttonOffset.x.cint + (
            if i == 1 and self.config.frameParts.left[0] == fpTitle: extent.width +
              self.config.textOffset.x.cint
            elif i == 1 and self.config.frameParts.left[0] == fpMaximize:
              self.config.buttonSize.cint + self.config.buttonOffset.x.cint
            elif i == 2:
              extent.width + self.config.textOffset.x.cint + self.config.buttonOffset.x.cint + self.config.buttonSize.cint
            else: 0), self.config.buttonOffset.y.cint)
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2],buttonColor[1],buttonColor[0],255))
      let img = readImage(self.config.closePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard XPutImage(self.dpy, client.frame.close, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)
    of fpMaximize:
      maximizeExists = true
      if not fileExists self.config.maximizePath: continue
      discard self.dpy.XMapWindow client.frame.maximize
      discard self.dpy.XMoveWindow(client.frame.maximize,
          self.config.buttonOffset.x.cint + (
            if i == 1 and self.config.frameParts.left[0] == fpTitle: 
              extent.width.cint
            elif i == 1 and self.config.frameParts.left[0] == fpClose:
              self.config.buttonSize.cint + self.config.buttonOffset.x.cint
            elif i == 2:
              extent.width + self.config.buttonOffset.x.cint + self.config.buttonSize.cint
            else: 0), self.config.buttonOffset.y.cint)
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2],buttonColor[1],buttonColor[0],255))
      let img = readImage(self.config.maximizePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard XPutImage(self.dpy, client.frame.maximize, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)
  for i, part in self.config.frameParts.center:
    case part:
    of fpTitle:
      if not closeExists: discard self.dpy.XUnmapWindow client.frame.close
      client.draw.XftDrawStringUtf8(addr client.color, self.font,
        (cint(attr.width div 2) - cint (extent.width div 2)) + (if i == 2: self.config.buttonSize.cint else: 0) + self.config.textOffset.x.cint,
            cint self.config.textOffset.y, cast[
          ptr char](cstring client.title), cint client.title.len)
    of fpClose:
      closeExists = true
      if not fileExists self.config.closePath: continue
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2],buttonColor[1],buttonColor[0],255))
      let img = readImage(self.config.closePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard self.dpy.XMoveWindow(client.frame.close, (if i ==
          0: -self.config.buttonOffset.x.cint else: self.config.buttonOffset.x.cint) +
          (if i == 1 and self.config.frameParts.center[0] == fpTitle and self.config.frameParts.center.len == 2:
            self.config.textOffset.x.cint + extent.width div 2
          elif i == 1 and self.config.frameParts.center[0] == fpTitle and self.config.frameParts.center.len > 2 and self.config.frameParts.center[1] == fpMaximize:
            -(extent.width div 2) - self.config.buttonSize.cint - self.config.buttonOffset.x.cint - self.config.textOffset.x.cint
          elif i == 2 and self.config.frameParts.center[0] == fpTitle:
            (extent.width div 2) + self.config.buttonOffset.x.cint + self.config.textOffset.x.cint + self.config.buttonSize.cint
          elif i == 1 and self.config.frameParts.center[0] == fpTitle:
            (extent.width div 2) + self.config.buttonOffset.x.cint + self.config.textOffset.x.cint - self.config.buttonSize.cint
          elif i == 1 and self.config.frameParts.center.len >= 2 and self.config.frameParts.center[0] == fpMaximize and self.config.frameParts.center[2] == fpTitle:
            # meh
            -(extent.width div 2)
          elif i == 2 and self.config.frameParts.center[1] == fpTitle:
            self.config.buttonSize.cint + extent.width div 2
          elif i == 1 and self.config.frameParts.center.len >= 2 and self.config.frameParts.center[2] == fpMaximize:
            0
          else:
            0) + (attr.width div 2) - (if i == 0 and self.config.frameParts.center.len > 1 and self.config.frameParts.center.find(fpTitle) != -1: self.config.buttonSize.cint +
          extent.width div 2 else: 0), self.config.buttonOffset.y.cint)
      discard self.dpy.XMapWindow client.frame.close
      discard XPutImage(self.dpy, client.frame.close, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)
    of fpMaximize:
      maximizeExists = true
      if not fileExists self.config.maximizePath: continue
      discard self.dpy.XMapWindow client.frame.maximize
      # M;T;C
      discard self.dpy.XMoveWindow(client.frame.maximize, (if i ==
          0: -self.config.buttonOffset.x.cint else: self.config.buttonOffset.x.cint) +
          (if i == 1 and self.config.frameParts.center[0] == fpTitle:
            self.config.textOffset.x.cint + extent.width div 2
          elif i == 1 and self.config.frameParts.center[0] == fpClose:
            -(extent.width div 2) - self.config.buttonOffset.x.cint
          elif i == 2 and self.config.frameParts.center[1] == fpTitle:
            extent.width div 2
          elif i == 2 and self.config.frameParts.center[1] == fpClose:
            extent.width div 2 + self.config.buttonSize.cint + self.config.buttonOffset.x.cint
          elif i == 0 and self.config.frameParts.center.len >= 2:
            # meh
            -(extent.width div 2) - self.config.buttonOffset.x.cint
          else: 0) + (attr.width div 2), self.config.buttonOffset.y.cint)
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2],buttonColor[1],buttonColor[0],255))
      let img = readImage(self.config.maximizePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard XPutImage(self.dpy, client.frame.maximize, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)
  for i, part in self.config.frameParts.right:
    case part:
    of fpTitle:
      if not closeExists: discard self.dpy.XUnmapWindow client.frame.close
      client.draw.XftDrawStringUtf8(addr client.color, self.font,
        (if self.config.frameParts.right.len == 1 or (self.config.frameParts.right.len == 2 and i == 1 and self.config.frameParts.right[0] in {fpClose, fpMaximize}):
          cint(attr.width) - (cint (extent.width) + self.config.textOffset.x.cint)
        elif self.config.frameParts.right.len == 2 and i == 0 and self.config.frameParts.right[1] in {fpClose, fpMaximize}:
          cint(attr.width) - (cint (extent.width) + self.config.textOffset.x.cint + self.config.buttonOffset.x.cint + self.config.buttonSize.cint)
        elif i == 1 and self.config.frameParts.right.len == 3 and self.config.frameParts.right[0] in {fpClose, fpMaximize}:
            cint(attr.width) - (cint (extent.width) + self.config.buttonSize.cint + self.config.buttonOffset.x.cint)
        elif i == 2:
          cint(attr.width) - (cint (extent.width) + self.config.textOffset.x.cint)
        elif i == 0 and self.config.frameParts.right.len == 3:
          cint(attr.width) - (extent.width.cint + self.config.buttonSize.cint * 2 + self.config.buttonOffset.x.cint * 3)
        else: 0), cint self.config.textOffset.y,
            cast[
          ptr char](cstring client.title), cint client.title.len)
    of fpClose:
      closeExists = true
      if not fileExists self.config.closePath: continue
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2], buttonColor[1], buttonColor[0], 255))
      let img = readImage(self.config.closePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard self.dpy.XMoveWindow(client.frame.close, (if i ==
          0: -self.config.buttonOffset.x.cint else: self.config.buttonOffset.x.cint) +
          (if i == 1 and self.config.frameParts.right.len == 2:
            -self.config.buttonSize.cint
          elif i == 1 and self.config.frameParts.right.len == 3:
            -extent.width - self.config.buttonOffset.x.cint
          elif i == 0 and self.config.frameParts.right.len == 2 and self.config.frameParts.right[1] == fpTitle:
            -extent.width
          elif i == 0 and self.config.frameParts.right.len == 2 and self.config.frameParts.right[1] == fpMaximize:
            -self.config.buttonSize.cint*2
          elif i == 0 and self.config.frameParts.right.len == 3:
            -self.config.buttonSize.cint - (self.config.buttonOffset.x.cint + extent.width)
          elif i == 2:
            -self.config.buttonSize.cint
          else: 0) + (attr.width) - self.config.buttonSize.cint - (if i == 0 and
          self.config.frameParts.center.len > 1: self.config.buttonSize.cint +
          extent.width div 2 else: 0), self.config.buttonOffset.y.cint)
      discard self.dpy.XMapWindow client.frame.close
      discard XPutImage(self.dpy, client.frame.close, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)
    of fpMaximize:
      maximizeExists = true
      if not fileExists self.config.maximizePath: continue
      discard self.dpy.XMapWindow client.frame.maximize
      discard self.dpy.XMoveWindow(client.frame.maximize,
          self.config.buttonOffset.x.cint + (
            if i == 1 and self.config.frameParts.right[0] == fpTitle and self.config.frameParts.right.len == 3:
              - self.config.buttonSize.cint * 2 - self.config.buttonOffset.x.cint
            elif i == 1 and self.config.frameParts.right[0] == fpTitle:
              - self.config.buttonSize.cint
            elif i == 1 and self.config.frameParts.right[0] == fpClose and self.config.frameParts.right.len == 3 and self.config.frameParts.right[2] == fpTitle:
              -extent.width - (self.config.buttonOffset.x.cint * 2)
            elif i == 1 and self.config.frameParts.right[0] == fpClose:
              - self.config.buttonOffset.x.cint * 2
            elif i == 2:
              -(self.config.buttonOffset.x.cint * 2)
            elif i == 0 and self.config.frameParts.right.len == 2 and self.config.frameParts.right[1] == fpClose:
              -(self.config.buttonOffset.x.cint * 4) - self.config.buttonSize.cint
            elif i == 0 and self.config.frameParts.right.len > 2 and self.config.frameParts.right[1] == fpClose:
              -(self.config.buttonOffset.x.cint * 3) - (self.config.buttonSize.cint + extent.width)
            elif i == 0 and self.config.frameParts.right.len >= 2 and self.config.frameParts.right[1] == fpTitle:
              -extent.width - self.config.buttonOffset.x.cint - self.config.buttonSize.cint*2
            elif i == 0 and self.config.frameParts.right.len == 1:
              - self.config.buttonOffset.x.cint * 2
            else: 0) + (attr.width) - self.config.buttonSize.cint, self.config.buttonOffset.y.cint)
      var
        screen = newImage(self.config.buttonSize.int, self.config.buttonSize.int)
      let buttonColor = cast[array[3, uint8]](fp)
      screen.fill(rgba(buttonColor[2],buttonColor[1],buttonColor[0],255))
      let img = readImage(self.config.maximizePath)
      screen.draw(
        img,
        # translate(vec2(100, 100)) *
        scale(vec2(self.config.buttonSize.int / img.width, self.config.buttonSize.int / img.height))
        # translate(vec2(-450, -450))
      )
      log $attr.depth
      var ctx = newContext screen
      # convert to BGRA
      var frameBufferEndian = ctx.image.data
      for i, color in frameBufferEndian:
        let x = color
        # RGBX -> BGRX
        frameBufferEndian[i].r = x.b
        frameBufferEndian[i].b = x.r
      var frameBuffer = addr frameBufferEndian[0]
      let image = XCreateImage(self.dpy, attr.visual, attr.depth.cuint, ZPixmap, 0, cast[cstring](
          frameBuffer), self.config.buttonSize.cuint, self.config.buttonSize.cuint, 8, cint(self.config.buttonSize*4))
      discard XPutImage(self.dpy, client.frame.maximize, gc, image, 0, 0, 0, 0, self.config.buttonSize.cuint, self.config.buttonSize.cuint)

proc eventLoop*(self: var Wm): void =
  if fileExists expandTilde "~/.config/worm/rc":
    discard startProcess expandTilde "~/.config/worm/rc"
  while true:
    discard self.dpy.XNextEvent(unsafeAddr self.currEv)
    self.dispatchEvent self.currEv

proc dispatchEvent*(self: var Wm; ev: XEvent): void =
  case ev.theType:
  #of ButtonPress: self.handleButtonPress ev.xbutton
  #of ButtonRelease: self.handleButtonRelease ev.xbutton
  #of MotionNotify: self.handleMotionNotify ev.xmotion
  #of MapRequest: self.handleMapRequest ev.xmaprequest
  of ConfigureRequest: self.handleConfigureRequest ev.xconfigurerequest
  #of ConfigureNotify: self.handleConfigureNotify ev.xconfigure
  #of UnmapNotify: self.handleUnmapNotify ev.xunmap
  #of DestroyNotify: self.handleDestroyNotify ev.xdestroywindow
  #of ClientMessage: self.handleClientMessage ev.xclient
  #of Expose: self.handleExpose ev.xexpose
  #of PropertyNotify: self.handlePropertyNotify ev.xproperty
  else: discard
