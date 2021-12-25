import ../wm
import ../types
import x11/[xlib]

proc handleConfigureRequest*(self: var Wm; ev: XConfigureRequestEvent): void =
  var changes = XWindowChanges(x: ev.x, y: ev.y, width: ev.width,
      height: ev.height, borderWidth: ev.borderWidth, sibling: ev.above,
      stackMode: ev.detail)
  discard self.dpy.XConfigureWindow(ev.window, cuint ev.valueMask, addr changes)
  if self.layout == lyTiling: self.tileWindows
