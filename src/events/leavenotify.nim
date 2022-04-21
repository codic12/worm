import ../wm, ../types
import x11/xlib
# import std/options

proc handleLeaveNotify*(self: var Wm; ev: XLeaveWindowEvent): void =
  for client in self.clients.mitems:
    if client.frame.close == ev.subwindow or client.frame.close == ev.window:
      client.frame.closeHovered = false
      self.renderTop client
      break
    elif client.frame.maximize == ev.subwindow or client.frame.maximize == ev.window:
      client.frame.maximizeHovered = false
      self.renderTop client
      break
    elif client.frame.minimize == ev.subwindow or client.frame.minimize == ev.window:
      client.frame.minimizeHovered = false
      self.renderTop client
      break