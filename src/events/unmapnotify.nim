import ../wm, ../types
import x11/[xlib,x]
import std/options

proc handleUnmapNotify*(self: var Wm; ev: XUnmapEvent): void =
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
