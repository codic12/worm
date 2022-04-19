import ../wm, ../types
import x11/xlib
# import std/options

proc handleEnterNotify*(self: var Wm; ev: XEnterWindowEvent): void =
  for client in self.clients.mitems:
    if client.frame.close == ev.subwindow or client.frame.close == ev.window:
      echo "Close enter"
    # echo client.frame.window
    # echo ev.subwindow
