import x11/[xlib, x, xft]
import ../wm, ../log, ../types
import std/[os, options, osproc, strutils]

proc handleButtonPress*(self: var Wm; ev: XButtonEvent): void =
  if ev.subwindow == None and ev.window == self.root and ev.button == 3:
    log "Root menu triggered (right click on root window). Attempting to launch root menu"
    if self.config.rootMenu != "" and fileExists expandTilde self.config.rootMenu:
      discard startProcess expandTilde self.config.rootMenu
    discard self.dpy.XAllowEvents(ReplayPointer, ev.time)
    return
  #if ev.subwindow == None or ev.window == self.root: return
  var
    close = false
    maximize = false
    minimize = false
  var clientOpt = self.findClient do (client: Client) -> bool:
    (
      if ev.window == client.frame.close:
        close = true
        close
      elif ev.window == client.frame.maximize:
        maximize = true
        maximize
      elif ev.window == client.frame.minimize:
        minimize = true
        minimize
      else:
        false) or client.frame.window == ev.subwindow or client.frame.title == ev.window
  if clientOpt.isNone and ev.button == 1:
    clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
    discard self.dpy.XAllowEvents(ReplayPointer, ev.time)
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  var 
    quitClose = false
    quitMaximize = false
    quitMinimize = false
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
  if minimize:
    # check if closable
    if self.config.frameParts.left.find(fpMinimize) == -1 and
        self.config.frameParts.center.find(fpMinimize) == -1 and
        self.config.frameParts.right.find(fpMinimize) == -1:
      quitMinimize = false
    else:
      self.minimizeClient client[]
      quitMinimize = true
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
  var fattr: XWindowAttributes
  discard self.dpy.XGetWindowAttributes(self.clients[self.focused.get].window, addr fattr)
  var color: XftColor
  discard self.dpy.XftColorAllocName(fattr.visual, fattr.colormap, cstring(
      "#" & self.config.textActivePixel.toHex 6), addr color)
  self.clients[self.focused.get].color = color
  self.renderTop self.clients[self.focused.get]
  for i, client in self.clients.mpairs:
    if self.focused.get.int == i: continue
    discard self.dpy.XSetWindowBorder(client.frame.window,
          self.config.borderInactivePixel)
    for window in [client.frame.top,client.frame.title,client.frame.window,client.frame.close,client.frame.maximize]:
      discard self.dpy.XSetWindowBackground(window, self.config.frameInactivePixel)
    var attr: XWindowAttributes
    discard self.dpy.XGetWindowAttributes(client.window, addr attr)
    var color: XftColor
    discard self.dpy.XftColorAllocName(attr.visual, attr.colormap, cstring(
        "#" & self.config.textInactivePixel.toHex 6), addr color)
    client.color = color
    self.renderTop client
    discard self.dpy.XSync false
    discard self.dpy.XFlush
