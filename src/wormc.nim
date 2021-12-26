import x11/[x, xlib, xutil]
import std/[strutils, os]
# import log
import atoms

converter toXBool(x: bool): XBool = x.XBool
converter toBool(x: XBool): bool = x.bool

type Layout = enum
  lyFloating, lyTiling

proc main: void =
  let dpy = XOpenDisplay nil
  if dpy == nil: return
  let ipcAtoms = dpy.getIpcAtoms
  let root = dpy.XDefaultRootWindow
  let params = commandLineParams()

  for i, param in commandLineParams():
    var data: array[5, clong]
    case param:
    of "border-active-pixel": data = [clong ipcAtoms[IpcBorderActivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "border-inactive-pixel": data = [clong ipcAtoms[IpcBorderInactivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "border-width": data = [clong ipcAtoms[IpcBorderWidth],
        clong params[i+1].parseInt, 0, 0, 0]
    of "frame-active-pixel": data = [clong ipcAtoms[IpcFrameActivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "frame-inactive-pixel": data = [clong ipcAtoms[IpcFrameInactivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "frame-height": data = [clong ipcAtoms[IpcFrameHeight],
        clong params[i+1].parseInt, 0, 0, 0]
    of "text-active-pixel": data = [clong ipcAtoms[IpcTextActivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "text-inactive-pixel": data = [clong ipcAtoms[IpcTextInactivePixel],
        clong params[i+1].parseInt, 0, 0, 0]
    of "gaps": data = [clong ipcAtoms[IpcGaps],
        clong params[i+1].parseInt, 0, 0, 0]
    of "text-font": # This is not as simple as sending a ClientMessage to the root window, because a string is involved; therefore, we must first do a bit of prepreation and then send a data-less msg
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcTextFont])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcTextFont], 0, 0, 0, 0]
    of "frame-left": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcFrameLeft])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcFrameLeft], 0, 0, 0, 0]
    of "frame-center": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcFrameCenter])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcFrameCenter], 0, 0, 0, 0]
    of "frame-right": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcFrameRight])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcFrameRight], 0, 0, 0, 0]
    of "root-menu": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcRootMenu])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcRootMenu], 0, 0, 0, 0]
    of "close-path": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcClosePath])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcClosePath], 0, 0, 0, 0]
    of "maximize-path": # Ditto
      var fontList = cstring params[i+1]
      var fontProp: XTextProperty
      discard dpy.XUtf8TextListToTextProperty(addr fontList, 1,
          XUTF8StringStyle, addr fontProp)
      dpy.XSetTextProperty(root, addr fontProp, ipcAtoms[IpcMaximizePath])
      discard XFree fontProp.value
      data = [clong ipcAtoms[IpcMaximizePath], 0, 0, 0, 0]
    of "text-offset": data = [clong ipcAtoms[IpcTextOffset],
        clong params[i+1].parseInt, clong params[i+2].parseInt, 0, 0]
    of "kill-client": data = [clong ipcAtoms[IpcKillClient], clong params[
        i+1].parseInt, 0, 0, 0]
    of "kill-active-client": data = [clong ipcAtoms[IpcKillClient], 0, 0, 0, 0]
    of "close-client": data = [clong ipcAtoms[IpcCloseClient], clong params[
        i+1].parseInt, 0, 0, 0]
    of "close-active-client": data = [clong ipcAtoms[IpcCloseClient], 0, 0, 0, 0]
    of "switch-tag": data = [clong ipcAtoms[IpcSwitchTag], clong params[
        i+1].parseInt, 0, 0, 0]
    of "layout": data = [clong ipcAtoms[IpcLayout], if params[i+1] ==
        "floating": clong lyFloating elif params[i+1] ==
        "tiling": clong lyTiling else: quit(1), 0, 0, 0]
    of "struts": data = [clong ipcAtoms[IpcStruts], clong params[i+1].parseInt,
        clong params[i+2].parseInt, clong params[i+3].parseInt, clong params[i+4].parseInt]
    of "move-tag": data = [clong ipcAtoms[IpcMoveTag], clong params[
        i+1].parseInt, clong params[i+2].parseInt, 0, 0]
    of "move-active-tag": data = [clong ipcAtoms[IpcMoveTag], clong params[
        i+1].parseInt, 0, 0, 0]
    of "master": data = [clong ipcAtoms[IpcMaster], clong params[i+1].parseInt,
        0, 0, 0]
    of "master-active": data = [clong ipcAtoms[IpcMaster], 0, 0, 0, 0]
    of "float": data = [clong ipcAtoms[IpcFloat], clong params[i+1].parseInt, 0, 0, 0]
    of "float-active": data = [clong ipcAtoms[IpcFloat], 0, 0, 0, 0]
    of "button-offset": data = [clong ipcAtoms[IpcButtonOffset],
        clong params[i+1].parseInt, clong params[i+2].parseInt, 0, 0]
    of "button-size": data = [clong ipcAtoms[IpcButtonSize], clong params[i+1].parseInt, 0, 0, 0]
    of "maximize-client": data = [clong ipcAtoms[IpcMaximizeClient], clong params[i+1].parseInt, 0, 0, 0]
    of "maximize-active-client": data = [clong ipcAtoms[IpcMaximizeClient], 0, 0, 0, 0]
    else: discard
    let event = XEvent(xclient: XClientMessageEvent(format: 32,
      theType: ClientMessage, serial: 0, sendEvent: true, display: dpy,
      window: root, messageType: ipcAtoms[IpcClientMessage],
      data: XClientMessageData(l: data)))
    discard dpy.XSendEvent(root, false, SubstructureNotifyMask, cast[ptr XEvent](
          unsafeAddr event))

  discard dpy.XFlush
  discard dpy.XSync false

when isMainModule: main()
