import ../wm
import x11/[xlib,x]
import std/options
import ../types

proc handleButtonRelease*(self: var Wm; ev: XButtonEvent): void =
  #if ev.subwindow == None or ev.window == self.root: return
  if self.motionInfo.isSome: discard self.dpy.XUngrabPointer CurrentTime
  self.motionInfo = none MotionInfo
  let clientOpt = self.findClient do (client: Client) ->
      bool: client.frame.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  self.renderTop client[]
