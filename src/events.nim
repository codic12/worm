import
  x11/[x, xlib],
  wm,
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
    unmapnotify,
    enternotify,
    leavenotify
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
  of EnterNotify: self.handleEnterNotify ev.xcrossing
  of LeaveNotify: self.handleLeaveNotify ev.xcrossing
  else: discard

proc eventLoop*(self: var Wm) =
  while true:
    discard self.dpy.XNextEvent(unsafeAddr self.currEv)
    self.dispatchEvent self.currEv

