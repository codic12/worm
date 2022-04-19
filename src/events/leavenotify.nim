import ../wm, ../types
import x11/xlib
# import std/options

proc handleLeaveNotify*(self: var Wm; ev: XLeaveWindowEvent): void =
  for client in self.clients:
    if client.frame.close == ev.subwindow or client.frame.close == ev.window: echo "Close leave"
