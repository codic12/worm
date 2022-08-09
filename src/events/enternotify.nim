import ../wm, ../types
import x11/xlib, x11/x
import std/options

proc handleEnterNotify*(self: var Wm; ev: XEnterWindowEvent): void =
  for client in self.clients.mitems:
    if client.frame.close == ev.subwindow or client.frame.close == ev.window:
      client.frame.closeHovered = true
      self.renderTop client
      break
    elif client.frame.maximize == ev.subwindow or client.frame.maximize == ev.window:
      client.frame.maximizeHovered = true
      self.renderTop client
      break
    elif client.frame.minimize == ev.subwindow or client.frame.minimize == ev.window:
      client.frame.minimizeHovered = true
      self.renderTop client
      break
    if self.focusMode == FocusFollowsMouse:
      let clientOpt = self.findClient do (client: Client) ->
          bool: client.frame.window == ev.window or client.frame.window == ev.subwindow
      if clientOpt.isNone: return
      let client = clientOpt.get[0]
      discard self.dpy.XRaiseWindow client.frame.window
      discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
      discard self.dpy.XMapWindow client.frame.window
      self.focused = some clientOpt.get[1]
      self.raiseClient clientOpt.get[0][]
