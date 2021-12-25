import ../wm, ../types, ../atoms
import x11/[xlib, x]
import std/options

proc handlePropertyNotify*(self: var Wm; ev: XPropertyEvent): void =
  let clientOpt = self.findClient do (client: Client) -> bool: client.window == ev.window
  if clientOpt.isNone: return
  let client = clientOpt.get[0]
  let title = block:
    var atr: Atom
    var afr: cint
    var nr: culong
    var bar: culong
    var prop_return: ptr char
    discard self.dpy.XGetWindowProperty(ev.window, self.netAtoms[NetWMName],
        0, high clong, false, self.dpy.XInternAtom("UTF8_STRING", false),
        addr atr, addr afr, addr nr, addr bar, addr prop_return)
    if prop_return == nil: discard self.dpy.XFetchName(ev.window, cast[
        ptr cstring](addr prop_return))
    $cstring prop_return
  if client.title == title: return
  client.title = title
  self.renderTop client[]
