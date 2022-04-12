import
  std/[strutils, os],
  x11/[x, xlib, xutil],
  atoms

converter toXBool(x: bool): XBool = x.XBool
converter toBool(x: XBool): bool = x.bool

type Layout = enum
  lyFloating, lyTiling

proc formatMess(a: Atom, params: varargs[string, `$`]): array[5, clong] =
  result[0] = a.clong

  for i in 1 ..< result.len:
    if i - 1 < params.len:
      result[i] = params[i - 1].parseInt().clong

proc sendStrPrep(dpy: PDisplay, a: Atom, param: string) =
  var
    fontList = param.cstring
    fontProp: XTextProperty
  discard dpy.XUtf8TextListToTextProperty(
    addr fontList,
    1,
    XUTF8StringStyle,
    addr fontProp
  )

  dpy.XSetTextProperty(
    dpy.XDefaultRootWindow,
    addr fontProp,
    a
  )
  discard XFree fontProp.value

proc getLayoutOrd(s: string): int =
  if s == "floating":
    result = lyFloating.ord
  elif s == "tiling":
    result = lyTiling.ord
  else:
    quit 1

proc main() =
  let dpy = XOpenDisplay nil

  if dpy == nil:
    return

  let
    ipcAtoms = dpy.getIpcAtoms
    root = dpy.XDefaultRootWindow
    params = commandLineParams()

  for i, param in commandLineParams():
    var data: array[5, clong]
    case param:
    of "border-active-pixel":
      data = ipcAtoms[IpcBorderActivePixel].formatMess(params[i+1])
    of "border-inactive-pixel":
      data = ipcAtoms[IpcBorderInactivePixel].formatMess(params[i+1])
    of "border-width":
      data = ipcAtoms[IpcBorderWidth].formatMess(params[i+1])
    of "frame-active-pixel":
      data = ipcAtoms[IpcFrameActivePixel].formatMess(params[i+1])
    of "frame-inactive-pixel":
      data = ipcAtoms[IpcFrameInactivePixel].formatMess(params[i+1])
    of "frame-height":
      data = ipcAtoms[IpcFrameHeight].formatMess(params[i+1])
    of "text-active-pixel":
      data = ipcAtoms[IpcTextActivePixel].formatMess(params[i+1])
    of "text-inactive-pixel":
      data = ipcAtoms[IpcTextInactivePixel].formatMess(params[i+1])
    of "gaps":
      data = ipcAtoms[IpcGaps].formatMess(params[i+1])

    # This is not as simple as sending a ClientMessage to the root window, 
    # because a string is involved; therefore, we must first do a bit of 
    # preparation and then send a data-less msg.
    of "text-font": 
      dpy.sendStrPrep(ipcAtoms[IpcTextFont], params[i+1])
      data = ipcAtoms[IpcTextFont].formatMess()
    of "frame-left":
      dpy.sendStrPrep(ipcAtoms[IpcFrameLeft], params[i+1])
      data = ipcAtoms[IpcFrameLeft].formatMess()
    of "frame-center":
      dpy.sendStrPrep(ipcAtoms[IpcFrameCenter], params[i+1])
      data = ipcAtoms[IpcFrameCenter].formatMess()
    of "frame-right":
      dpy.sendStrPrep(ipcAtoms[IpcFrameRight], params[i+1])
      data = ipcAtoms[IpcFrameRight].formatMess()
    of "root-menu":
      dpy.sendStrPrep(ipcAtoms[IpcRootMenu], params[i+1])
      data = formatMess ipcAtoms[IpcRootMenu]
    of "close-active-path":
      dpy.sendStrPrep(ipcAtoms[IpcCloseActivePath], params[i+1])
      data = ipcAtoms[IpcCloseActivePath].formatMess()
    of "close-inactive-path":
      dpy.sendStrPrep(ipcAtoms[IpcCloseInactivePath], params[i+1])
      data = ipcAtoms[IpcCloseInactivePath].formatMess()
    of "maximize-active-path":
      dpy.sendStrPrep(ipcAtoms[IpcMaximizeActivePath], params[i+1])
      data = ipcAtoms[IpcMaximizeActivePath].formatMess()
    of "maximize-inactive-path":
      dpy.sendStrPrep(ipcAtoms[IpcMaximizeInactivePath], params[i+1])
      data = ipcAtoms[IpcMaximizeInactivePath].formatMess()
    of "minimize-active-path":
      dpy.sendStrPrep(ipcAtoms[IpcMinimizeActivePath], params[i+1])
      data = ipcAtoms[IpcMinimizeActivePath].formatMess()
    of "minimize-inactive-path":
      dpy.sendStrPrep(ipcAtoms[IpcMinimizeInactivePath], params[i+1])
      data = ipcAtoms[IpcMinimizeInactivePath].formatMess()
    of "decoration-disable":
      dpy.sendStrPrep(ipcAtoms[IpcDecorationDisable], params[i+1])
      data = ipcAtoms[IpcDecorationDisable].formatMess()
    of "text-offset":
      data = ipcAtoms[IpcTextOffset].formatMess(params[i+1], params[i+2])
    of "kill-client":
      data = ipcAtoms[IpcKillClient].formatMess(params[i+1])
    of "kill-active-client":
      data = ipcAtoms[IpcKillClient].formatMess()
    of "close-client":
      data = ipcAtoms[IpcCloseClient].formatMess(params[i+1])
    of "close-active-client":
      data = ipcAtoms[IpcCloseClient].formatMess()
    of "switch-tag":
      data = ipcAtoms[IpcSwitchTag].formatMess(params[i+1])
    of "layout":
      data = ipcAtoms[IpcLayout].formatMess(getLayoutOrd params[i+1])
    of "struts":
      data = ipcAtoms[IpcStruts].formatMess(
        params[i+1], params[i+2], params[i+3], params[i+4]
      )
    of "move-tag":
      data = ipcAtoms[IpcMoveTag].formatMess(params[i+1], params[i+2])
    of "move-active-tag":
      data = ipcAtoms[IpcMoveTag].formatMess(params[i+1])
    of "master":
      data = ipcAtoms[IpcMaster].formatMess(params[i+1])
    of "master-active":
      data = ipcAtoms[IpcMaster].formatMess()
    of "float":
      data = ipcAtoms[IpcFloat].formatMess(params[i+1])
    of "float-active":
      data = ipcAtoms[IpcFloat].formatMess()
    of "button-offset":
      data = ipcAtoms[IpcButtonOffset].formatMess(params[i+1], params[i+2])
    of "button-size":
      data = ipcAtoms[IpcButtonSize].formatMess(params[i+1])
    of "maximize-client":
      data = ipcAtoms[IpcMaximizeClient].formatMess(params[i+1])
    of "maximize-active-client":
      data = ipcAtoms[IpcMaximizeClient].formatMess()
    of "minimize-client":
      data = ipcAtoms[IpcMinimizeClient].formatMess(params[i+1])
    of "minimize-active-client":
      data = ipcAtoms[IpcMinimizeClient].formatMess()

    else: discard

    let event = XEvent(
      xclient: XClientMessageEvent(
        format: 32,
        theType: ClientMessage,
        serial: 0,
        sendEvent: true,
        display: dpy,
        window: root,
        messageType: ipcAtoms[IpcClientMessage],
        data: XClientMessageData(l: data)
      )
    )
    discard dpy.XSendEvent(
      root,
      false,
      SubstructureNotifyMask,
      cast[ptr XEvent](unsafeAddr event)
    )

  discard dpy.XFlush
  discard dpy.XSync false

when isMainModule:
  main()
