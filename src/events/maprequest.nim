import ../wm, ../types, ../atoms, ../log
import std/[options, strutils]
import x11/[x, xlib, xft, xatom, xutil]
import regex

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

proc handleMapRequest*(self: var Wm; ev: XMapRequestEvent): void =
  var attr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(ev.window, addr attr)
  if attr.overrideRedirect: return
  let wintype = getProperty[Atom](self.dpy, ev.window, self.netAtoms[
      NetWMWindowType])
  type Hints = object
    flags, functions, decorations: culong
    inputMode: clong
    status: culong
  if wintype.isSome and wintype.get in {self.netAtoms[
      NetWMWindowTypeDock], self.netAtoms[NetWMWindowTypeDropdownMenu],
          self.netAtoms[NetWMWindowTypePopupMenu], self.netAtoms[
          NetWMWindowTypeTooltip], self.netAtoms[
          NetWMWindowTypeNotification], self.netAtoms[NetWMWindowTypeDesktop]}:
    discard self.dpy.XMapWindow ev.window
    return # Don't manage irregular windows
  let hints = getProperty[Hints](self.dpy, ev.window, self.dpy.XInternAtom(
      "_MOTIF_WM_HINTS", false))
  var frameHeight = self.config.frameHeight
  var csd = false
  if hints.isSome and hints.get.flags == 2 and hints.get.decorations == 0:
    frameHeight = 0
    csd = true
  var max = false
  var state = block:
    var
      typ: Atom
      fmt: cint
      nitem: culong
      baf: culong
      props: ptr cuchar
    discard self.dpy.XGetWindowProperty(ev.window, self.netAtoms[NetWMState], 0,
        high clong, false, AnyPropertyType, addr typ, addr fmt, addr nitem,
        addr baf, addr props)
    props
  if state != nil:
    if cast[int](state[]) in {int self.netAtoms[NetWMStateMaximizedHorz],
        int self.netAtoms[NetWMStateMaximizedVert]}:
      max = true
  var chr: XClassHint
  discard self.dpy.XGetClassHint(ev.window, addr chr)
  block:
    for thing in self.noDecorList:
      var m: RegexMatch
      log $chr.resClass
      log $thing
      if ($chr.resClass).match thing:
        csd = true
        frameHeight = 0
  var frameAttr = XSetWindowAttributes(backgroundPixel: culong self.config.frameActivePixel,
      borderPixel: self.config.borderActivePixel, colormap: attr.colormap)
  let frame = self.dpy.XCreateWindow(self.root, attr.x +
      self.config.struts.left.cint, attr.y + self.config.struts.top.cint, cuint attr.width, cuint attr.height +
      cint frameHeight,
      cuint self.config.borderWidth, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  discard self.dpy.XSelectInput(frame, ExposureMask or SubstructureNotifyMask or
      SubstructureRedirectMask)
  discard self.dpy.XSelectInput(ev.window, PropertyChangeMask)
  discard self.dpy.XReparentWindow(ev.window, frame, 0,
      cint frameHeight)
  # WM_NAME must be set for GTK drag&drop and xprop
  # https://github.com/i3/i3/blob/dba30fc9879b42e6b89773c81e1067daa2bb6e23/src/x.c#L1065
  let wm_state: uint8 = NormalState
  discard self.dpy.XChangeProperty(
    ev.window,
    self.dpy.XInternAtom("WM_STATE".cstring, false),
    XaWindow,
    8,
    PropModeReplace,
    cast[cstring](unsafeAddr wm_state),
    1
  )
  let top = self.dpy.XCreateWindow(frame, 0, 0,
      cuint attr.width, cuint frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let titleWin = self.dpy.XCreateWindow(top, 0, 0,
      cuint attr.width, cuint frameHeight, 0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let close = self.dpy.XCreateWindow(top, cint attr.width -
      self.config.buttonSize.cint, 0, self.config.buttonSize.cuint, cuint frameHeight,
      0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let maximize = self.dpy.XCreateWindow(top, cint attr.width -
      self.config.buttonSize.cint, 0, self.config.buttonSize.cuint, cuint frameHeight,
      0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  let minimize = self.dpy.XCreateWindow(top, cint attr.width -
      self.config.buttonSize.cint, 0, self.config.buttonSize.cuint, cuint frameHeight,
      0, attr.depth,
      InputOutput,
      attr.visual, CWBackPixel or CWBorderPixel or CWColormap, addr frameAttr)
  for window in [frame, ev.window, top, titleWin]: discard self.dpy.XMapWindow window
  let draw = self.dpy.XftDrawCreate(titleWin, attr.visual, attr.colormap)
  var color: XftColor
  discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring("#" &
      self.config.textActivePixel.toHex 6), addr color)
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
    for win in [close, maximize, minimize]: discard self.dpy.XGrabButton(1, mask, win,
        true, ButtonPressMask or PointerMotionMask, GrabModeAsync, GrabModeAsync,
            None, None)
  for mask in [uint32 0, Mod2Mask, LockMask,
         Mod3Mask, Mod2Mask or LockMask,
        LockMask or Mod3Mask, Mod2Mask or Mod3Mask,
        Mod2Mask or LockMask or Mod3Mask]:
    discard self.dpy.XGrabButton(1, mask, ev.window, true, ButtonPressMask,
        GrabModeSync, GrabModeSync, None, None)
  self.clients.add Client(window: ev.window, frame: Frame(window: frame,
      top: top, close: close, maximize: maximize, minimize: minimize,
      title: titleWin), draw: draw, color: color,
      title: $title, tags: self.tags, floating: self.layout == lyFloating,
      frameHeight: frameHeight, csd: csd, class: $chr.resClass, maximized: max)
  if max:
    self.maximizeClient(self.clients[self.clients.len - 1], true)
  self.updateClientList
  let extents = [self.config.borderWidth, self.config.borderWidth,
      self.config.borderWidth+frameHeight, self.config.borderWidth]
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
  self.raiseClient self.clients[self.focused.get]
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
