import ../wm, ../types
import x11/[xlib, x]
import std/options

proc handleExpose*(self: var Wm; ev: XExposeEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  discard self.dpy.XMapWindow client.frame.window
  discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
  discard self.dpy.XRaiseWindow client.frame.window

