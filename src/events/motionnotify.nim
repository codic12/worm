import ../wm, ../types, ../log
import std/options
import x11/[xlib, x]

proc handleMotionNotify*(self: var Wm; ev: XMotionEvent): void =
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
      cint client.frameHeight).cuint)
  let conf = XConfigureEvent(theType: ConfigureNotify, display: self.dpy,
      event: client.window, window: client.window, x: motionInfo.attr.x + (
      if motionInfo.start.button == 1: xdiff else: 0), y: motionInfo.attr.y + (
      if motionInfo.start.button == 1: ydiff else: 0), width: cint 1.max(
          motionInfo.attr.width + (if motionInfo.start.button ==
              3: xdiff else: 0)).cuint, height: cint 1.max(
          motionInfo.attr.height +
          (if motionInfo.start.button == 3: ydiff else: 0) -
      cint client.frameHeight).cuint)
  log $client.frameHeight
  discard self.dpy.XSendEvent(client.window, false, StructureNotifyMask, cast[
      ptr XEvent](unsafeAddr conf))
  discard self.dpy.XResizeWindow(client.frame.top, 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, cuint client.frameHeight)
  discard self.dpy.XResizeWindow(client.frame.title, 1.max(
      motionInfo.attr.width + (if motionInfo.start.button ==
      3: xdiff else: 0)).cuint, cuint client.frameHeight)

