# Worm v0.0.1 ( Nim version )
# License: MIT

import std/[options, sequtils, strutils, osproc, os]
import x11/[xlib, x, xft, xinerama, xatom, xutil, xrender]
import log
import atoms
import pixie

converter toXBool(x: bool): XBool = x.XBool
converter toBool(x: XBool): bool = x.bool

type
  Layout = enum
    lyFloating, lyTiling
  FramePart = enum
    fpTitle, fpClose, fpMaximize
  Geometry = object
    x, y: int
    width, height: uint
  MotionInfo = object
    start: XButtonEvent
    attr: XWindowAttributes
  Frame = object
    window, top, title: Window
    close, maximize: Window # button parts
  Client = object
    window: Window
    frame: Frame
    draw: ptr XftDraw
    color: XftColor
    title: string
    beforeGeom: Option[Geometry] # Previous geometry *of the frame* pre-fullscreen.
    fullscreen: bool # Whether this client is currently fullscreened or not (EWMH, or otherwise ig)
    floating: bool # If tiling is on, whether this window is currently floating or not. If it's floating it won't be included in the tiling.
    tags: TagSet
  Config = object
    borderActivePixel, borderInactivePixel, borderWidth: uint
    frameActivePixel, frameInactivePixel, frameHeight: uint
    textPixel: uint
    textOffset, buttonOffset: tuple[x, y: uint]
    gaps: int # TODO: fix the type errors and change this to unsigned integers.
    struts: tuple[top, bottom, left, right: uint]
    frameParts: tuple[left, center, right: seq[FramePart]]
    buttonSize: uint # always square FOR NOW
    rootMenu: string
    closePath, maximizePath: string
  TagSet = array[9, bool] # distinct
  Wm = object
    dpy: ptr XDisplay
    root: Window
    motionInfo: Option[MotionInfo]
    currEv: XEvent
    clients: seq[Client]
    font: ptr XftFont
    netAtoms: array[NetAtom, Atom]
    ipcAtoms: array[IpcAtom, Atom]
    config: Config
    focused: Option[uint]
    tags: TagSet
    layout: Layout

proc defaultTagSet(): TagSet = [true, false, false, false, false, false, false,
    false, false]

proc switchTag(self: var TagSet; tag: uint8): void =
  for i, _ in self: self[i] = false
  self[tag] = true

func getProperty[T](
  dpy: ptr Display;
  window: Window;
  property: Atom
): Option[T] =
  # TODO: proper names when I'm less lazy and can write it all out
  var
    a: Atom
    b: cint
    c: culong
    d: culong
    e: ptr T
  discard XGetWindowProperty(
    dpy,
    window,
    property,
    0,
    high clong,
    false,
    AnyPropertyType,
    addr a,
    addr b,
    addr c,
    addr d,
    cast[ptr ptr char](addr e)
  )
  if c > 0: return some e[] else: result.reset

proc newWm: Wm
proc eventLoop(self: var Wm): void
proc dispatchEvent(self: var Wm; ev: XEvent): void
proc handleButtonPress(self: var Wm; ev: XButtonEvent): void
proc handleButtonRelease(self: var Wm; ev: XButtonEvent): void
proc handleMotionNotify(self: var Wm; ev: XMotionEvent): void
proc handleMapRequest(self: var Wm; ev: XMapRequestEvent): void
proc handleConfigureRequest(self: var Wm; ev: XConfigureRequestEvent): void
proc handleUnmapNotify(self: var Wm; ev: XUnmapEvent): void
proc handleDestroyNotify(self: var Wm; ev: XDestroyWindowEvent): void
proc handleClientMessage(self: var Wm; ev: XClientMessageEvent): void
proc handleConfigureNotify(self: var Wm; ev: XConfigureEvent): void
proc handleExpose(self: var Wm; ev: XExposeEvent): void
proc handlePropertyNotify(self: var Wm; ev: XPropertyEvent): void
func findClient(self: var Wm; predicate: proc(client: Client): bool): Option[(
    ptr Client, uint)]
proc updateClientList(self: Wm): void
proc updateTagState(self: Wm): void
proc tileWindows(self: var Wm): void
proc renderTop(self: var Wm; client: var Client): void
proc maximizeClient(self: var Wm; client: var Client): void

proc newWm: Wm =
  let dpy = XOpenDisplay nil
  if dpy == nil: quit 1
  log "Opened display"
  let root = dpy.XDefaultRootWindow
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

proc eventLoop(self: var Wm): void =
  if fileExists expandTilde "~/.config/worm/rc":
    discard startProcess expandTilde "~/.config/worm/rc"
  while true:
    discard self.dpy.XNextEvent(unsafeAddr self.currEv)
    self.dispatchEvent self.currEv

proc dispatchEvent(self: var Wm; ev: XEvent): void =
  case ev.theType:
  of ButtonPress: self.handleButtonPress ev.xbutton
  of ButtonRelease: self.handleButtonRelease ev.xbutton
  of MotionNotify: self.handleMotionNotify ev.xmotion
  of MapRequest: self.handleMapRequest ev.xmaprequest
  of ConfigureRequest: self.handleConfigureRequest ev.xconfigurerequest
  of ConfigureNotify: self.handleConfigureNotify ev.xconfigure
  of UnmapNotify: self.handleUnmapNotify ev.xunmap
  of DestroyNotify: self.handleDestroyNotify ev.xdestroywindow
  of ClientMessage: self.handleClientMessage ev.xclient
  of Expose: self.handleExpose ev.xexpose
  of PropertyNotify: self.handlePropertyNotify ev.xproperty
  else: discard

proc handleButtonPress(self: var Wm; ev: XButtonEvent): void =
  if ev.subwindow == None and ev.window == self.root and ev.button == 3:
    log "Root menu"
    if self.config.rootMenu != "" and fileExists expandTilde self.config.rootMenu:
      discard startProcess expandTilde self.config.rootMenu
    discard self.dpy.XAllowEvents(ReplayPointer, ev.time)
    return
  #if ev.subwindow == None or ev.window == self.root: return
  var close = false
  var maximize = false
  var clientOpt = self.findClient do (client: Client) -> bool:
    (
      if ev.window == client.frame.close:
        close = true
        close
      elif ev.window == client.frame.maximize:
        maximize = true
        maximize
      else:
        false) or client.frame.window == ev.subwindow or client.frame.title == ev.window
  if clientOpt.isNone and ev.button == 1:
    clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
    discard self.dpy.XAllowEvents(ReplayPointer, ev.time)
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  var quitClose = false
  var quitMaximize = false
  if close:
    # check if closable
    if self.config.frameParts.left.find(fpClose) == -1 and
        self.config.frameParts.center.find(fpClose) == -1 and
        self.config.frameParts.right.find(fpClose) == -1:
      quitClose = false
    else:
      let cm = XEvent(xclient: XClientMessageEvent(format: 32,
          theType: ClientMessage, serial: 0, sendEvent: true, display: self.dpy,
          window: client.window, messageType: self.dpy.XInternAtom(
              "WM_PROTOCOLS", false),
          data: XClientMessageData(l: [clong self.dpy.XInternAtom(
              "WM_DELETE_WINDOW", false), CurrentTime, 0, 0, 0])))
      discard self.dpy.XSendEvent(client.window, false, NoEventMask, cast[
          ptr XEvent](unsafeAddr cm))
      quitClose = true
  if quitClose: return
  if maximize:
    # check if closable
    if self.config.frameParts.left.find(fpMaximize) == -1 and
        self.config.frameParts.center.find(fpMaximize) == -1 and
        self.config.frameParts.right.find(fpMaximize) == -1:
      quitMaximize = false
    else:
      self.maximizeClient client[]
      quitMaximize = true
  if quitMaximize: return
  discard self.dpy.XGrabPointer(client.frame.window, true, PointerMotionMask or
      ButtonReleaseMask, GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)
  self.motionInfo = some MotionInfo(start: ev, attr: attr)
  discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
  for window in [client.frame.window, client.window]: discard self.dpy.XRaiseWindow window
  self.focused = some clientOpt.get[1]
  discard self.dpy.XSetWindowBorder(self.clients[self.focused.get].frame.window,
      self.config.borderActivePixel)
  for win in [
    self.clients[self.focused.get].frame.window,
    self.clients[self.focused.get].frame.top,
    self.clients[self.focused.get].frame.title,
    self.clients[self.focused.get].frame.close,
    self.clients[self.focused.get].frame.maximize
  ]:
    discard self.dpy.XSetWindowBackground(win, self.config.frameActivePixel)
    self.renderTop self.clients[self.focused.get]
    discard self.dpy.XSync false
    discard self.dpy.XFlush
  for i, client in self.clients.mpairs:
    if self.focused.get.int == i: continue
    discard self.dpy.XSetWindowBorder(client.frame.window,
          self.config.borderInactivePixel)
    for window in [client.frame.top,client.frame.title,client.frame.window,client.frame.close,client.frame.maximize]:
      discard self.dpy.XSetWindowBackground(window, self.config.frameInactivePixel)
    self.renderTop client
    discard self.dpy.XSync false
    discard self.dpy.XFlush

proc handleButtonRelease(self: var Wm; ev: XButtonEvent): void =
  #if ev.subwindow == None or ev.window == self.root: return
  if self.motionInfo.isSome: discard self.dpy.XUngrabPointer CurrentTime
  self.motionInfo = none MotionInfo
  let clientOpt = self.findClient do (client: Client) ->
      bool: client.frame.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  self.renderTop client[]
  # ? we need to do something from the fullscreen/unfullscreen code I think.

proc handleMotionNotify(self: var Wm; ev: XMotionEvent): void =
  #if ev.subwindow == None or ev.window == self.root
  if self.motionInfo.isNone: return
  let clientOpt = self.findClient do (client: Client) ->
      bool:
    client.frame.window == ev.window or client.frame.title == ev.window
    # false
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  if client.fullscreen: return
  let motionInfo = self.motionInfo.get
  while self.dpy.XCheckTypedEvent(MotionNotify, addr self.currEv): discard
  let
    xdiff = ev.x_root - motionInfo.start.x_root
    ydiff = ev.y_root - motionInfo.start.y_root
  # todo hoist w/h out
  discard self.dpy.XMoveResizeWindow(client.frame.window, motionInfo.attr.x + (
      if motionInfo.start.button == 1: xdiff else: 0), motionInfo.attr.y + (
      if motionInfo.start.button == 1: ydiff else: 0), 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, 1.max(motionInfo.attr.height + (
      if motionInfo.start.button == 3: ydiff else: 0)).cuint)
  discard self.dpy.XResizeWindow(client.window, 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, 1.max(motionInfo.attr.height + (
      if motionInfo.start.button == 3: ydiff else: 0) -
      cint self.config.frameHeight).cuint)
  let conf = XConfigureEvent(theType: ConfigureNotify, display: self.dpy,
      event: client.window, window: client.window, x: motionInfo.attr.x + (
      if motionInfo.start.button == 1: xdiff else: 0), y: motionInfo.attr.y + (
      if motionInfo.start.button == 1: ydiff else: 0), width: cint 1.max(
          motionInfo.attr.width + (if motionInfo.start.button ==
              3: xdiff else: 0)).cuint, height: cint 1.max(
          motionInfo.attr.height +
          (if motionInfo.start.button == 3: ydiff else: 0) -
      cint self.config.frameHeight).cuint)
  discard self.dpy.XSendEvent(client.window, false, StructureNotifyMask, cast[
      ptr XEvent](unsafeAddr conf))
  discard self.dpy.XResizeWindow(client.frame.top, 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, cuint self.config.frameHeight)
  discard self.dpy.XResizeWindow(client.frame.title, 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, cuint self.config.frameHeight)
  # if motionInfo.attr.y + (if motionInfo.start.button == 1: ydiff else: 0) <= 0: # snapping which doesn't really work properly
  #   var scrNo: cint
  #   var scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](self.dpy.XineramaQueryScreens(addr scrNo))
  #   discard self.dpy.XMoveResizeWindow(client.frame.window, 0, 0, cuint scrInfo[0].width, cuint scrInfo[0].height)
  #   discard self.dpy.XMoveResizeWindow(client.window, 0, 0, cuint scrInfo[0].width, cuint(scrInfo[0].height) - cuint self.config.frameHeight)
  #   discard self.dpy.XUngrabPointer CurrentTime

proc handleMapRequest(self: var Wm; ev: XMapRequestEvent): void =
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(ev.window, addr attr)
  if attr.overrideRedirect: return
  let wintype = getProperty[Atom](self.dpy, ev.window, self.netAtoms[
      NetWMWindowType])
  if wintype.isSome and wintype.get in {self.netAtoms[
      NetWMWindowTypeDock], self.netAtoms[NetWMWindowTypeDropdownMenu],
          self.netAtoms[NetWMWindowTypePopupMenu], self.netAtoms[
          NetWMWindowTypeTooltip], self.netAtoms[
          NetWMWindowTypeNotification]}:
    discard self.dpy.XMapWindow ev.window
    return # Don't manage irregular windows
  var frameAttr = XSetWindowAttributes(backgroundPixel: culong self.config.frameActivePixel,
      borderPixel: self.config.borderActivePixel, colormap: attr.colormap)
  let frame = self.dpy.XCreateWindow(self.root, attr.x, attr.y,
      cuint attr.width, cuint attr.height + cint self.config.frameHeight,
      cuint self.config.borderWidth, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  discard self.dpy.XSelectInput(frame, ExposureMask or SubstructureNotifyMask or
      SubstructureRedirectMask)
  discard self.dpy.XSelectInput(ev.window, PropertyChangeMask)
  discard self.dpy.XReparentWindow(ev.window, frame, 0,
      cint self.config.frameHeight)
  let top = self.dpy.XCreateWindow(frame, 0, 0,
      cuint attr.width, cuint self.config.frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let titleWin = self.dpy.XCreateWindow(top, 0, 0,
      cuint attr.width, cuint self.config.frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let close = self.dpy.XCreateWindow(top, cint attr.width - self.config.buttonSize.cint, 0,
      self.config.buttonSize.cuint, cuint self.config.frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let maximize = self.dpy.XCreateWindow(top, cint attr.width - self.config.buttonSize.cint, 0,
      self.config.buttonSize.cuint, cuint self.config.frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  for window in [frame, ev.window, top, titleWin]: discard self.dpy.XMapWindow window
  let draw = self.dpy.XftDrawCreate(titleWin, attr.visual, attr.colormap)
  var color: XftColor
  discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring("#" &
      self.config.textPixel.toHex 6), addr color)
  var title = block:
    var atr: Atom
    var afr: cint
    var nr: culong
    var bar: culong
    var prop_return: ptr char
    discard self.dpy.XGetWindowProperty(ev.window, self.netAtoms[NetWMName],
        0, high clong, false, self.dpy.XInternAtom("UTF8_STRING", false),
        addr atr, addr afr, addr nr, addr bar, addr prop_return)
    if prop_return == nil: discard self.dpy.XFetchName(ev.window, cast[
        ptr cstring](addr prop_return))
    cstring prop_return
  if title == nil: title = "Unnamed Window" # why the heck does this window not have a name?!
  for button in [1'u8, 3]:
    for mask in [uint32 0, Mod2Mask, LockMask,
         Mod3Mask, Mod2Mask or LockMask,
        LockMask or Mod3Mask, Mod2Mask or Mod3Mask,
        Mod2Mask or LockMask or Mod3Mask]:
      discard self.dpy.XGrabButton(button, mask, titleWin, true,
        ButtonPressMask or
        PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None)
  for mask in [uint32 0, Mod2Mask, LockMask,
         Mod3Mask, Mod2Mask or LockMask,
        LockMask or Mod3Mask, Mod2Mask or Mod3Mask,
        Mod2Mask or LockMask or Mod3Mask]:
    for win in [close, maximize]: discard self.dpy.XGrabButton(1, mask, win, true, ButtonPressMask or
        PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None)
  for mask in [uint32 0, Mod2Mask, LockMask,
         Mod3Mask, Mod2Mask or LockMask,
        LockMask or Mod3Mask, Mod2Mask or Mod3Mask,
        Mod2Mask or LockMask or Mod3Mask]:
    discard self.dpy.XGrabButton(1, mask, ev.window, true, ButtonPressMask,
        GrabModeSync, GrabModeSync, None, None)
  self.clients.add Client(window: ev.window, frame: Frame(window: frame,
      top: top, close: close, maximize: maximize, title: titleWin), draw: draw, color: color,
      title: $title, tags: self.tags, floating: self.layout == lyFloating)
  self.updateClientList
  let extents = [self.config.borderWidth, self.config.borderWidth,
      self.config.borderWidth+self.config.frameHeight, self.config.borderWidth]
  discard self.dpy.XChangeProperty(
    ev.window,
    self.netAtoms[NetFrameExtents],
    XaCardinal,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr extents),
    4
  )
  for window in [frame, ev.window, top]: discard self.dpy.XRaiseWindow window
  discard self.dpy.XSetInputFocus(ev.window, RevertToPointerRoot, CurrentTime)
  self.focused = some uint self.clients.len - 1
  for i, client in self.clients:
    if (self.focused.isSome and uint(i) != self.focused.get) or self.focused.isNone: discard self.dpy.XSetWindowBorder(client.frame.window,
            self.config.borderInactivePixel)
  if self.layout == lyTiling: self.tileWindows
  while true:
    var currEv: XEvent
    if self.dpy.XNextEvent(addr currEv) != Success: continue
    if currEv.theType == Expose:
      self.renderTop self.clients[self.clients.len - 1]
      break
  for client in self.clients:
    for i, tag in client.tags:
      if not tag: continue
      discard self.dpy.XChangeProperty(
        client.window,
        self.netAtoms[NetWMDesktop],
        XaCardinal,
        32,
        PropModeReplace,
        cast[cstring](unsafeAddr i),
        1
      )

proc handleConfigureRequest(self: var Wm; ev: XConfigureRequestEvent): void =
  var changes = XWindowChanges(x: ev.x, y: ev.y, width: ev.width,
      height: ev.height, borderWidth: ev.borderWidth, sibling: ev.above,
      stackMode: ev.detail)
  discard self.dpy.XConfigureWindow(ev.window, cuint ev.valueMask, addr changes)
  if self.layout == lyTiling: self.tileWindows

proc handleUnmapNotify(self: var Wm; ev: XUnmapEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  discard self.dpy.XUnmapWindow client.frame.window
  self.clients.del clientOpt.get[1]
  self.updateClientList
  discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
  self.focused.reset # TODO: focus last window
  for i, locClient in self.clients:
    discard self.dpy.XSetWindowBorder(locClient.frame.window,
          self.config.borderInactivePixel)
  if self.layout == lyTiling: self.tileWindows

proc handleDestroyNotify(self: var Wm; ev: XDestroyWindowEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  discard self.dpy.XDestroyWindow client.frame.window
  self.clients.del clientOpt.get[1]
  self.updateClientList
  discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
  self.focused.reset # TODO: focus last window
  for i, locClient in self.clients:
    discard self.dpy.XSetWindowBorder(locClient.frame.window,
          self.config.borderInactivePixel)
  if self.layout == lyTiling: self.tileWindows
  
proc handleClientMessage(self: var Wm; ev: XClientMessageEvent): void =
  if ev.messageType == self.netAtoms[NetWMState]:
    let clientOpt = self.findClient do (client: Client) ->
        bool: client.window == ev.window
    if clientOpt.isNone: return
    let client = clientOpt.get[0]
    if ev.format != 32: return # check we can access the union member
    if (ev.data.l[1] == int self.netAtoms[NetWMStateFullScreen]) or (
        ev.data.l[2] == int self.netAtoms[NetWMStateFullScreen]):
      if ev.data.l[0] == 1 and not client.fullscreen: # Client is asking to be fullscreened
        log "Fullscreening client"
        var attr: XWindowAttributes
        discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)
        client.beforeGeom = some Geometry(x: attr.x, y: attr.y,
            width: uint attr.width, height: uint attr.height)
        var scrNo: cint
        var scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
            self.dpy.XineramaQueryScreens(addr scrNo))
        discard self.dpy.XSetWindowBorderWidth(client.frame.window, 0)
        # where the hell is our window at
        var x: int
        var y: int
        var width: uint
        var height: uint
        if scrno == 1:
          # 1st monitor, cuz only one
          x = 0
          y = 0
          width = scrInfo[0].width.uint
          height = scrInfo[0].height.uint
        else:
          var cumulWidth = 0
          var cumulHeight = 0
          for i in countup(0, scrNo - 1):
            cumulWidth += scrInfo[i].width
            cumulHeight += scrInfo[i].height
            if attr.x <= cumulWidth - attr.width and attr.y <= cumulHeight - attr.height:
              x = scrInfo[i].xOrg
              y = scrInfo[i].yOrg
              width = scrInfo[i].width.uint
              height = scrInfo[i].height.uint
        discard self.dpy.XMoveResizeWindow(
          client.frame.window, cint x, cint y, cuint width, cuint height)
        discard self.dpy.XMoveResizeWindow(
          client.window, 0, 0, cuint width, cuint height)
        for window in [client.window, client.frame.window]: discard self.dpy.XRaiseWindow window
        discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
        var arr = [self.netAtoms[NetWMStateFullScreen]]
        # change the property
        discard self.dpy.XChangeProperty(client.window, self.netAtoms[
            NetWMState], XaAtom, 32, PropModeReplace, cast[cstring](
                addr arr), 1)
        client.fullscreen = true
      elif ev.data.l[0] == 0 and client.fullscreen:
        log "Unfullscreening client"
        client.fullscreen = false
        discard self.dpy.XMoveResizeWindow(client.frame.window,
            cint client.beforeGeom.get.x, cint client.beforeGeom.get.y,
            cuint client.beforeGeom.get.width,
            cuint client.beforeGeom.get.height)
        discard self.dpy.XMoveResizeWindow(client.window,
            0, cint self.config.frameHeight,
            cuint client.beforeGeom.get.width,
            cuint client.beforeGeom.get.height - self.config.frameHeight)
        discard self.dpy.XChangeProperty(client.window, self.netAtoms[
            NetWMState], XaAtom, 32, PropModeReplace, cast[cstring]([]), 0)
        self.renderTop client[]
        discard self.dpy.XSetWindowBorderWidth(client.frame.window,
            cuint self.config.borderWidth)
  elif ev.messageType == self.netAtoms[NetActiveWindow]:
    if ev.format != 32: return
    let clientOpt = self.findClient do (client: Client) ->
        bool: client.window == ev.window
    if clientOpt.isNone: return
    let client = clientOpt.get[0]
    discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
    discard self.dpy.XRaiseWindow client.frame.window
    self.renderTop client[]
    self.focused = some clientOpt.get[1]
    discard self.dpy.XSetWindowBorder(client.frame.window,
        self.config.borderActivePixel)
    for i, locClient in self.clients:
      if uint(i) != clientOpt.get[1]: discard self.dpy.XSetWindowBorder(locClient.frame.window,
            self.config.borderInactivePixel)
  elif ev.messageType == self.netAtoms[NetCurrentDesktop]:
    self.tags.switchTag uint8 ev.data.l[0]
    self.updateTagState
    let numdesk = [ev.data.l[0]]
    discard self.dpy.XChangeProperty(
      self.root,
      self.netAtoms[NetCurrentDesktop],
      XaCardinal,
      32,
      PropModeReplace,
      cast[cstring](unsafeAddr numdesk),
      1
    )
    discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
    self.focused = none uint
    if self.clients.len == 0: return
    var lcot = -1
    for i, c in self.clients:
      if c.tags == self.tags: lcot = i
    if lcot == -1: return
    self.focused = some uint lcot
    discard self.dpy.XSetInputFocus(self.clients[self.focused.get].window, RevertToPointerRoot, CurrentTime)
    discard self.dpy.XSetWindowBorder(self.clients[self.focused.get].frame.window,
      self.config.borderActivePixel)
    for i, locClient in self.clients.mpairs:
      if uint(i) != self.focused.get: discard self.dpy.XSetWindowBorder(locClient.frame.window, self.config.borderInactivePixel)
      self.renderTop locClient
    if self.layout == lyTiling: self.tileWindows
  elif ev.messageType == self.ipcAtoms[IpcClientMessage]: # Register events from our IPC-based event system
    if ev.format != 32: return # check we can access the union member
    if ev.data.l[0] == clong self.ipcAtoms[IpcBorderInactivePixel]:
      log "Changing inactive border pixel to " & $ev.data.l[1]
      self.config.borderInactivePixel = uint ev.data.l[1]
      for i, client in self.clients:
        if (self.focused.isSome and uint(i) != self.focused.get) or
            self.focused.isNone: discard self.dpy.XSetWindowBorder(
            client.frame.window, self.config.borderInactivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcBorderActivePixel]:
      log "Changing active border pixel to " & $ev.data.l[1]
      self.config.borderActivePixel = uint ev.data.l[1]
      if self.focused.isSome: discard self.dpy.XSetWindowBorder(self.clients[
          self.focused.get].frame.window, self.config.borderActivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcBorderWidth]:
      log "Changing border width to " & $ev.data.l[1]
      self.config.borderWidth = uint ev.data.l[1]
      for client in self.clients:
        discard self.dpy.XSetWindowBorderWidth(client.frame.window,
            cuint self.config.borderWidth)
        # In the case that the border width changed, the outer frame's dimensions also changed.
        # To the X perspective because borders are handled by the server the actual window
        # geometry remains the same. However, we need to still inform the client of the change
        # by changing the _NET_FRAME_EXTENTS property, if it's EWMH compliant it may respect
        # this.
        let extents = [self.config.borderWidth, self.config.borderWidth,
        self.config.borderWidth+self.config.frameHeight,
        self.config.borderWidth]
        discard self.dpy.XChangeProperty(
          client.window,
          self.netAtoms[NetFrameExtents],
          XaCardinal,
          32,
          PropModeReplace,
          cast[cstring](unsafeAddr extents),
          4
        )
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameInactivePixel]:
      log "Changing frame pixel to " & $ev.data.l[1]
      self.config.frameInactivePixel = uint ev.data.l[1]
      for i, client in self.clients:
        if self.focused.isSome and i == self.focused.get.int: return
        for window in [client.frame.top,client.frame.title,client.frame.window,client.frame.close,client.frame.maximize]: discard self.dpy.XSetWindowBackground(window,
            cuint self.config.frameInactivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameActivePixel]:
      log "Changing frame pixel to " & $ev.data.l[1]
      self.config.frameActivePixel = uint ev.data.l[1]
      if self.focused.isNone: return
      for win in [
        self.clients[self.focused.get].frame.window,
        self.clients[self.focused.get].frame.top,
        self.clients[self.focused.get].frame.title,
        self.clients[self.focused.get].frame.close,
        self.clients[self.focused.get].frame.maximize
      ]: discard self.dpy.XSetWindowBackground(win,
            cuint self.config.frameActivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameHeight]:
      log "Changing frame height to " & $ev.data.l[1]
      self.config.frameHeight = uint ev.data.l[1]
      for client in self.clients:
        var attr: XWindowAttributes
        discard self.dpy.XGetWindowAttributes(client.window, addr attr)
        discard self.dpy.XResizeWindow(client.frame.window, cuint attr.width,
            cuint attr.height + cint self.config.frameHeight)
        discard self.dpy.XMoveResizeWindow(client.window, 0,
            cint self.config.frameHeight, cuint attr.width, cuint attr.height)
        # See the comment in the setter for IpcBorderWidth. The exact same thing applies for
        # IpcFrameWidth, except in this case the geometry from X11 perspective is actually impacted.
        let extents = [self.config.borderWidth, self.config.borderWidth,
        self.config.borderWidth+self.config.frameHeight,
        self.config.borderWidth]
        discard self.dpy.XChangeProperty(
          client.window,
          self.netAtoms[NetFrameExtents],
          XaCardinal,
          32,
          PropModeReplace,
          cast[cstring](unsafeAddr extents),
          4
        )
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextPixel]:
      log "Chaging text pixel to " & $ev.data.l[1]
      self.config.textPixel = uint ev.data.l[1]
      for client in mitems self.clients:
        var attr: XWindowAttributes
        discard self.dpy.XGetWindowAttributes(client.window, addr attr)
        var color: XftColor
        discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring(
            "#" & self.config.textPixel.toHex 6), addr color)
        client.color = color
        self.renderTop client
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextFont]:
      log "IpcTextFont"
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcTextFont])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing text font to " & $fontList[0]
      self.font = self.dpy.XftFontOpenName(XDefaultScreen self.dpy, fontList[0])
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextOffset]:
      log "Changing text offset to (x: " & $ev.data.l[1] & ", y: " & $ev.data.l[
          2] & ")"
      self.config.textOffset = (x: uint ev.data.l[1], y: uint ev.data.l[2])
      for client in self.clients.mitems: self.renderTop client
    elif ev.data.l[0] == clong self.ipcAtoms[IpcKillClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      discard self.dpy.XKillClient window
    elif ev.data.l[0] == clong self.ipcAtoms[IpcCloseClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      let cm = XEvent(xclient: XClientMessageEvent(format: 32,
        theType: ClientMessage, serial: 0, sendEvent: true, display: self.dpy,
        window: window, messageType: self.dpy.XInternAtom("WM_PROTOCOLS",
            false),
        data: XClientMessageData(l: [clong self.dpy.XInternAtom(
            "WM_DELETE_WINDOW", false), CurrentTime, 0, 0, 0])))
      discard self.dpy.XSendEvent(window, false, NoEventMask, cast[ptr XEvent](unsafeAddr cm))
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaximizeClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      var client: Client
      if self.focused.isSome:
        client = self.clients[self.focused.get]
      else:
        var co = self.findClient do (c: Client) -> bool: c.window == Window ev.data.l[1]
        if co.isNone: return
        client = (co.get)[0][]
      self.maximizeClient client
    elif ev.data.l[0] == clong self.ipcAtoms[IpcSwitchTag]:
      self.tags.switchTag uint8 ev.data.l[1] - 1
      self.updateTagState
      let numdesk = [ev.data.l[1] - 1]
      discard self.dpy.XChangeProperty(
        self.root,
        self.netAtoms[NetCurrentDesktop],
        XaCardinal,
        32,
        PropModeReplace,
        cast[cstring](unsafeAddr numdesk),
        1
      )
      discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
      self.focused = none uint
      if self.clients.len == 0: return
      var lcot = -1
      for i, c in self.clients:
        if c.tags == self.tags: lcot = i
      if lcot == -1: return
      self.focused = some uint lcot
      discard self.dpy.XSetInputFocus(self.clients[self.focused.get].window, RevertToPointerRoot, CurrentTime)
      discard self.dpy.XSetWindowBorder(self.clients[self.focused.get].frame.window,
        self.config.borderActivePixel)
      for i, locClient in self.clients.mpairs:
        if uint(i) != self.focused.get: discard self.dpy.XSetWindowBorder(locClient.frame.window,
              self.config.borderInactivePixel)
        self.renderTop locClient
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcLayout]:
      # We recieve this IPC event when a client such as wormc wishes to change the layout (eg, floating -> tiling)
      if ev.data.l[1] notin {0, 1}: return
      self.layout = Layout ev.data.l[1]
      for i, _ in self.clients:
        self.clients[i].floating = self.layout == lyFloating
      log $self.clients
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcGaps]:
      self.config.gaps = int ev.data.l[1]
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaster]:
      # Get the index of the client, for swapping.
      # this isn't actually done yet
      let newMasterIdx = block:
        if ev.data.l[1] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[1]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      var
        currMasterOpt: Option[Client] = none Client
        currMasterIdx: uint = 0
      for i, client in self.clients:
        if client.tags == self.tags: # We only care about clients on the current tag.
          if currMasterOpt.isNone: # This must be the first client on the tag, otherwise master would not be nil; therefore, we promote it to master.
            currMasterOpt = some self.clients[i]
            currMasterIdx = uint i
      if currMasterOpt.isNone: return
      let currMaster = currMasterOpt.get
      self.clients[currMasterIdx] = self.clients[newMasterIdx]
      self.clients[newMasterIdx] = currMaster
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcStruts]:
      self.config.struts = (
        top: uint ev.data.l[1],
        bottom: uint ev.data.l[2],
        left: uint ev.data.l[3],
        right: uint ev.data.l[4]
      )
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMoveTag]: # [tag, wid | 0, 0, 0, 0]
      log $ev.data.l
      let tag = ev.data.l[1] - 1
      let client = block:
        if ev.data.l[2] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[2]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      self.clients[client].tags = [false, false, false, false, false, false,
          false, false, false]
      self.clients[client].tags[tag] = true
      self.updateTagState
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFloat]:
      let client = block:
        if ev.data.l[1] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[1]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      self.clients[client].floating = true
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameLeft]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameLeft])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          else: continue
      self.config.frameParts.left = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameCenter]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameCenter])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          else: continue
      self.config.frameParts.center = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameRight]:
      log "Frame Right"
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameRight])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          else: continue
      self.config.frameParts.right = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcButtonOffset]:
      self.config.buttonOffset = (
        x: uint ev.data.l[1],
        y: uint ev.data.l[2]
      )
      log $self.config.buttonOffset
    elif ev.data.l[0] == clong self.ipcAtoms[IpcButtonSize]:
      self.config.buttonSize = uint ev.data.l[1]
    elif ev.data.l[0] == clong self.ipcAtoms[IpcRootMenu]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcRootMenu])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing root menu path to " & $fontList[0]
      self.config.rootMenu = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcClosePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcClosePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing root menu path to " & $fontList[0]
      self.config.closePath = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaximizePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcMaximizePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing root menu path to " & $fontList[0]
      self.config.maximizePath = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value

proc handleConfigureNotify(self: var Wm; ev: XConfigureEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  if not client.fullscreen: # and not (ev.x == 0 and ev.y == cint self.config.frameHeight):
    discard self.dpy.XResizeWindow(client.frame.window, cuint ev.width,
        cuint ev.height + cint self.config.frameHeight)
    discard self.dpy.XMoveWindow(client.window, 0, cint self.config.frameHeight)
  # if self.layout == lyTiling: self.tileWindows

func findClient(self: var Wm; predicate: proc(client: Client): bool): Option[(
    ptr Client, uint)] =
  for i, client in self.clients:
    if predicate client:
      return some((addr self.clients[i], uint i))
  return none((ptr Client, uint))

proc updateClientList(self: Wm): void =
  let wins = self.clients.map do (client: Client) ->
      Window: client.window # Retrieve all the underlying X11 windows from the client list.
  if wins.len == 0: return
  discard self.dpy.XChangeProperty(
    self.root,
    self.netAtoms[NetClientList],
    XaWindow,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr wins[0]),
    cint wins.len
  )

proc handleExpose(self: var Wm; ev: XExposeEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
  discard self.dpy.XRaiseWindow client.frame.window

proc handlePropertyNotify(self: var Wm; ev: XPropertyEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  let title = block:
    var atr: Atom
    var afr: cint
    var nr: culong
    var bar: culong
    var prop_return: ptr char
    discard self.dpy.XGetWindowProperty(ev.window, self.netAtoms[NetWMName],
        0, high clong, false, self.dpy.XInternAtom("UTF8_STRING", false),
        addr atr, addr afr, addr nr, addr bar, addr prop_return)
    if prop_return == nil: discard self.dpy.XFetchName(ev.window, cast[
        ptr cstring](addr prop_return))
    $cstring prop_return
  if client.title == title: return
  client.title = title
  self.renderTop client[]

proc updateTagState(self: Wm): void =
  for client in self.clients:
    for i, tag in client.tags:
      if self.tags[i] and tag:
        discard self.dpy.XMapWindow client.frame.window
        break
      discard self.dpy.XUnmapWindow client.frame.window

proc tileWindows(self: var Wm): void =
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
    
proc main: void =
  log "Starting Worm v0.2 (rewrite)"
  var wm = newWm()
  wm.eventLoop

proc renderTop(self: var Wm; client: var Client): void =
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

proc maximizeClient(self: var Wm; client: var Client): void =
  # maximize the provided client
  var scrNo: cint
  var scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
      self.dpy.XineramaQueryScreens(addr scrNo))
  let masterWidth =
    uint scrInfo[0].width -
        (self.config.struts.left.cint + self.config.struts.right.cint + cint self.config.borderWidth*2)
  discard self.dpy.XMoveResizeWindow(client.frame.window,
      cint self.config.struts.left, cint self.config.struts.top,
      cuint masterWidth, cuint scrInfo[0].height -
      self.config.struts.top.int16 - self.config.struts.bottom.int16 -
      cint self.config.borderWidth*2)
  discard self.dpy.XResizeWindow(client.window, cuint masterWidth,
      cuint scrInfo[0].height - self.config.struts.top.cint -
      self.config.struts.bottom.cint - self.config.frameHeight.cint -
      cint self.config.borderWidth*2)
  self.renderTop client

when isMainModule:
  main()
