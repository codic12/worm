import ../wm, ../types
import x11/xlib
import std/options

proc handleConfigureNotify*(self: var Wm; ev: XConfigureEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  if not client.fullscreen: # and not (ev.x == 0 and ev.y == cint self.config.frameHeight):
    discard self.dpy.XResizeWindow(client.frame.window, cuint ev.width,
        cuint ev.height + cint self.config.frameHeight)
    discard self.dpy.XMoveWindow(client.window, 0, cint self.config.frameHeight)
  # if self.layout == lyTiling: self.tileWindows

