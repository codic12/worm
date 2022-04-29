import ../wm
import ../types
import x11/[xlib]
import std/options

proc handleConfigureRequest*(self: var Wm; ev: XConfigureRequestEvent): void =
  var changes = XWindowChanges(x: ev.x, y: ev.y, width: ev.width,
      height: ev.height, borderWidth: ev.borderWidth, sibling: ev.above,
      stackMode: ev.detail)
  discard self.dpy.XConfigureWindow(ev.window, cuint ev.valueMask, addr changes)
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  if ev.x != 0 and ev.y != 0: discard self.dpy.XMoveWindow(client.frame.window, ev.x, ev.y)
  if self.layout == lyTiling: self.tileWindows
  self.renderTop client[]