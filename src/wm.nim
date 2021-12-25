import std/[options, os]
import x11/[xlib, x, xft, xatom]
import types
import atoms
import log
import events/configurerequest

converter toXBool*(x: bool): XBool = x.XBool
converter toBool*(x: XBool): bool = x.bool

type
  Wm = object
    dpy: ptr Display
    root: Window
    motionInfo: Option[MotionInfo]
    currEv: XEvent
    clients: seq[Client]
    font: ptr XftFont
    netAtoms: array[NetAtom, Atom]
    ipcAtoms: array[IpcAtom, Atom]
    config: Config
    focused: Option[uint]
    tags: TagSet
    layout: Layout

# event handlers
proc handleButtonPress(self: var Wm; ev: XButtonEvent): void
proc handleButtonRelease(self: var Wm; ev: XButtonEvent): void
proc handleMotionNotify(self: var Wm; ev: XMotionEvent): void
proc handleMapRequest(self: var Wm; ev: XMapRequestEvent): void
proc handleConfigureRequest(self: var Wm; ev: XConfigureRequestEvent): void
proc handleUnmapNotify(self: var Wm; ev: XUnmapEvent): void
proc handleDestroyNotify(self: var Wm; ev: XDestroyWindowEvent): void
proc handleClientMessage(self: var Wm; ev: XClientMessageEvent): void
proc handleConfigureNotify(self: var Wm; ev: XConfigureEvent): void
proc handleExpose(self: var Wm; ev: XExposeEvent): void
proc handlePropertyNotify(self: var Wm; ev: XPropertyEvent): void
# others
proc newWm: Wm
proc eventLoop(self: var Wm): void
proc dispatchEvent(self: var Wm; ev: XEvent): void
func findClient(self: var Wm; predicate: proc(client: Client): bool): Option[(
    ptr Client, uint)]
proc updateClientList(self: Wm): void
proc updateTagState(self: Wm): void
proc tileWindows(self: var Wm): void
proc renderTop(self: var Wm; client: var Client): void
proc maximizeClient(self: var Wm; client: var Client): void

proc newWm: Wm =
  let dpy = XOpenDisplay nil
  if dpy == nil: quit 1
  log "Opened display"
  let root = XDefaultRootWindow dpy
  for button in [1'u8, 3]:
    # list from sxhkd (Mod2Mask NumLock, Mod3Mask ScrollLock, LockMask CapsLock).
    for mask in [uint32 Mod1Mask, Mod1Mask or Mod2Mask, Mod1Mask or LockMask,
        Mod1Mask or Mod3Mask, Mod1Mask or Mod2Mask or LockMask, Mod1Mask or
        LockMask or Mod3Mask, Mod1Mask or Mod2Mask or Mod3Mask, Mod1Mask or
        Mod2Mask or LockMask or Mod3Mask]:
      discard dpy.XGrabButton(button, mask, root, true, ButtonPressMask or
        PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None)
  discard dpy.XSelectInput(root, SubstructureRedirectMask or SubstructureNotifyMask or ButtonPressMask)
  let font = dpy.XftFontOpenName(XDefaultScreen dpy, "Noto Sans Mono:size=11")
  let netAtoms = getNetAtoms dpy
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetSupportingWMCheck],
    XaWindow,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr root),
    1
  )
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetSupported],
    XaAtom,
    32,
    PropModeReplace,
    cast[cstring](unsafeAddr netAtoms),
    netAtoms.len.cint
  )
  let wmname = "worm".cstring
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetWMName],
    dpy.XInternAtom("UTF8_STRING", false),
    8,
    PropModeReplace,
    wmname,
    4
  )
  var numdesk = [9]
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetNumberOfDesktops],
    XaCardinal,
    32,
    PropModeReplace,
    cast[cstring](addr numdesk),
    1
  )
  numdesk = [0]
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetCurrentDesktop],
    XaCardinal,
    32,
    PropModeReplace,
    cast[cstring](addr numdesk),
    1
  )
  discard dpy.XChangeProperty(
    root,
    netAtoms[NetClientList],
    XaWindow,
    32,
    PropModeReplace,
    nil,
    0
  )
  discard XSetErrorHandler proc(dpy: ptr Display;
      err: ptr XErrorEvent): cint {.cdecl.} = 0
  discard dpy.XSync false
  discard dpy.XFlush
  Wm(dpy: dpy, root: root, motionInfo: none MotionInfo, font: font,
      netAtoms: netAtoms, ipcAtoms: getIpcAtoms dpy, config: Config(
          borderActivePixel: 0x7499CC, borderInactivePixel: 0x000000,
          borderWidth: 1,
          frameActivePixel: 0x161821, frameInactivePixel: 0x666666, frameHeight: 30,
          textPixel: 0xffffff, textOffset: (x: uint 10, y: uint 20), gaps: 0, buttonSize: 14,
              struts: (top: uint 10, bottom: uint 40, left: uint 10,
              right: uint 10)), tags: defaultTagSet(),
              layout: lyFloating) # The default configuration is reasonably sane, and for now based on the Iceberg colorscheme. It may be changed later; it's recommended for users to write their own.

