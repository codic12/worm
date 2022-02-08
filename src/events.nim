import
  std/[os, osproc],
  x11/[x, xlib],
  wm,
  log,
  events/[
    buttonpress,
    buttonrelease,
    clientmessage,
    configurenotify,
    configurerequest,
    destroynotify,
    expose,
    maprequest,
    motionnotify,
    propertynotify,
    unmapnotify
  ]

proc dispatchEvent*(self: var Wm; ev: XEvent) =
  case ev.theType:
  of ButtonPress: self.handleButtonPress ev.xbutton
  of ButtonRelease: self.handleButtonRelease ev.xbutton
  of MotionNotify: self.handleMotionNotify ev.xmotion
  of MapRequest: self.handleMapRequest ev.xmaprequest
  of ConfigureRequest: self.handleConfigureRequest ev.xconfigurerequest
  of ConfigureNotify: self.handleConfigureNotify ev.xconfigure
  of UnmapNotify: self.handleUnmapNotify ev.xunmap
  of DestroyNotify: self.handleDestroyNotify ev.xdestroywindow
  of ClientMessage: self.handleClientMessage ev.xclient
  of Expose: self.handleExpose ev.xexpose
  of PropertyNotify: self.handlePropertyNotify ev.xproperty
  else: discard

proc eventLoop*(self: var Wm) =
  if fileExists expandTilde "~/.config/worm/rc":
    log "config file found, loading..."
    discard startProcess expandTilde "~/.config/worm/rc"
    log "config file loaded!"
  while true:
    discard self.dpy.XNextEvent(unsafeAddr self.currEv)
    self.dispatchEvent self.currEv

