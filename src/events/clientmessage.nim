import ../wm, ../atoms, ../types, ../log
import x11/[xlib, x, xinerama, xatom, xft, xutil]
import std/[options, strutils]
import regex

proc handleClientMessage*(self: var Wm; ev: XClientMessageEvent) =
  if ev.messageType == self.netAtoms[NetWMState]:
    var clientOpt = self.findClient do (client: Client) ->
        bool: client.window == ev.window
    if clientOpt.isNone: return
    var client = clientOpt.get[0]
    if ev.format != 32: return # check we can access the union member
    if (ev.data.l[1] == int self.netAtoms[NetWMStateFullScreen]) or (
        ev.data.l[2] == int self.netAtoms[NetWMStateFullScreen]):
      if ev.data.l[0] == 1 and not client.fullscreen: # Client is asking to be fullscreened
        log "Fullscreening client"
        var attr: XWindowAttributes
        discard self.dpy.XGetWindowAttributes(client.frame.window, addr attr)
        client.beforeGeom = some Geometry(x: attr.x, y: attr.y,
            width: uint attr.width, height: uint attr.height)
        var scrNo: cint
        var scrInfo = cast[ptr UncheckedArray[XineramaScreenInfo]](
            self.dpy.XineramaQueryScreens(addr scrNo))
        discard self.dpy.XSetWindowBorderWidth(client.frame.window, 0)
        # where the hell is our window at
        var x: int
        var y: int
        var width: uint
        var height: uint
        if scrno == 1:
          # 1st monitor, cuz only one
          x = 0
          y = 0
          width = scrInfo[0].width.uint
          height = scrInfo[0].height.uint
        else:
          var cumulWidth = 0
          var cumulHeight = 0
          for i in countup(0, scrNo - 1):
            cumulWidth += scrInfo[i].width
            cumulHeight += scrInfo[i].height
            if attr.x <= cumulWidth - attr.width:
              x = scrInfo[i].xOrg
              y = scrInfo[i].yOrg
              width = scrInfo[i].width.uint
              height = scrInfo[i].height.uint
        discard self.dpy.XMoveResizeWindow(
          client.frame.window, cint x, cint y, cuint width, cuint height)
        discard self.dpy.XMoveResizeWindow(
          client.window, 0, 0, cuint width, cuint height)
        for window in [client.window, client.frame.window]: discard self.dpy.XRaiseWindow window
        discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
        var arr = [self.netAtoms[NetWMStateFullScreen]]
        # change the property
        discard self.dpy.XChangeProperty(client.window, self.netAtoms[
            NetWMState], XaAtom, 32, PropModeReplace, cast[cstring](
                addr arr), 1)
        client.fullscreen = true
      elif ev.data.l[0] == 0 and client.fullscreen:
        log "Unfullscreening client"
        client.fullscreen = false
        discard self.dpy.XMoveResizeWindow(client.frame.window,
            cint client.beforeGeom.get.x, cint client.beforeGeom.get.y,
            cuint client.beforeGeom.get.width,
            cuint client.beforeGeom.get.height)
        discard self.dpy.XMoveResizeWindow(client.window,
            0, cint self.config.frameHeight,
            cuint client.beforeGeom.get.width,
            cuint client.beforeGeom.get.height - self.config.frameHeight)
        discard self.dpy.XChangeProperty(client.window, self.netAtoms[
            NetWMState], XaAtom, 32, PropModeReplace, cast[cstring]([]), 0)
        self.renderTop client[]
        discard self.dpy.XSetWindowBorderWidth(client.frame.window,
            cuint self.config.borderWidth)
    elif (ev.data.l[1] == int self.netAtoms[NetWMStateMaximizedHorz]) or (ev.data.l[1] == int self.netAtoms[NetWMStateMaximizedVert]) or 
       (ev.data.l[2] == int self.netAtoms[NetWMStateMaximizedVert]) or (ev.data.l[2] == int self.netAtoms[NetWMStateMaximizedHorz]):
        if ev.data.l[0] == 2:
          self.maximizeClient client[]
        elif ev.data.l[0] == 1: # add max
          if client.maximized: return
          self.maximizeClient client[]
        elif ev.data.l[0] == 0: # rm max
          if not client.maximized: return
          self.maximizeClient client[]
        else:
          # wtf
          discard
  elif ev.messageType == self.netAtoms[NetActiveWindow]:
    if ev.format != 32: return
    let clientOpt = self.findClient do (client: Client) ->
        bool: client.window == ev.window
    if clientOpt.isNone: return
    let client = clientOpt.get[0]
    discard self.dpy.XRaiseWindow client.frame.window
    discard self.dpy.XSetInputFocus(client.window, RevertToPointerRoot, CurrentTime)
    discard self.dpy.XMapWindow client.frame.window
    self.focused = some clientOpt.get[1]
    self.raiseClient clientOpt.get[0][]
  elif ev.messageType == self.netAtoms[NetCurrentDesktop]:
    self.tags.switchTag uint8 ev.data.l[0]
    self.updateTagState
    let numdesk = [ev.data.l[0]]
    discard self.dpy.XChangeProperty(
      self.root,
      self.netAtoms[NetCurrentDesktop],
      XaCardinal,
      32,
      PropModeReplace,
      cast[cstring](unsafeAddr numdesk),
      1
    )
    discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
    self.focused = none uint
    if self.clients.len == 0: return
    var lcot = -1
    for i, c in self.clients:
      if c.tags == self.tags: lcot = i
    if lcot == -1: return
    self.focused = some uint lcot
    self.raiseClient self.clients[self.focused.get]
    if self.layout == lyTiling: self.tileWindows
  elif ev.messageType == self.ipcAtoms[IpcClientMessage]: # Register events from our IPC-based event system
    if ev.format != 32: return # check we can access the union member
    if ev.data.l[0] == clong self.ipcAtoms[IpcBorderInactivePixel]:
      log "Changing inactive border pixel to " & $ev.data.l[1]
      self.config.borderInactivePixel = uint ev.data.l[1]
      for i, client in self.clients:
        if (self.focused.isSome and uint(i) != self.focused.get) or
            self.focused.isNone: discard self.dpy.XSetWindowBorder(
            client.frame.window, self.config.borderInactivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcBorderActivePixel]:
      log "Changing active border pixel to " & $ev.data.l[1]
      self.config.borderActivePixel = uint ev.data.l[1]
      if self.focused.isSome: discard self.dpy.XSetWindowBorder(self.clients[
          self.focused.get].frame.window, self.config.borderActivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcBorderWidth]:
      log "Changing border width to " & $ev.data.l[1]
      self.config.borderWidth = uint ev.data.l[1]
      for client in self.clients:
        discard self.dpy.XSetWindowBorderWidth(client.frame.window,
            cuint self.config.borderWidth)
        # In the case that the border width changed, the outer frame's dimensions also changed.
        # To the X perspective because borders are handled by the server the actual window
        # geometry remains the same. However, we need to still inform the client of the change
        # by changing the _NET_FRAME_EXTENTS property, if it's EWMH compliant it may respect
        # this.
        let extents = [self.config.borderWidth, self.config.borderWidth,
        self.config.borderWidth+self.config.frameHeight,
        self.config.borderWidth]
        discard self.dpy.XChangeProperty(
          client.window,
          self.netAtoms[NetFrameExtents],
          XaCardinal,
          32,
          PropModeReplace,
          cast[cstring](unsafeAddr extents),
          4
        )
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameInactivePixel]:
      log "Changing frame inactive pixel to " & $ev.data.l[1]
      self.config.frameInactivePixel = uint ev.data.l[1]
      for i, client in self.clients:
        if self.focused.isSome and i == self.focused.get.int: return
        for window in [client.frame.top,client.frame.title,client.frame.window,client.frame.close,client.frame.maximize]: discard self.dpy.XSetWindowBackground(window,
            cuint self.config.frameInactivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameActivePixel]:
      log "Changing frame active pixel to " & $ev.data.l[1]
      self.config.frameActivePixel = uint ev.data.l[1]
      if self.focused.isNone: return
      for win in [
        self.clients[self.focused.get].frame.window,
        self.clients[self.focused.get].frame.top,
        self.clients[self.focused.get].frame.title,
        self.clients[self.focused.get].frame.close,
        self.clients[self.focused.get].frame.maximize
      ]: discard self.dpy.XSetWindowBackground(win,
            cuint self.config.frameActivePixel)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameHeight]:
      log "Changing frame height to " & $ev.data.l[1]
      self.config.frameHeight = uint ev.data.l[1]
      for client in mitems self.clients:
        if client.csd: return
        client.frameHeight = self.config.frameHeight
        var attr: XWindowAttributes
        discard self.dpy.XGetWindowAttributes(client.window, addr attr)
        discard self.dpy.XResizeWindow(client.frame.window, cuint attr.width,
            cuint attr.height + cint self.config.frameHeight)
        discard self.dpy.XMoveResizeWindow(client.window, 0,
            cint self.config.frameHeight, cuint attr.width, cuint attr.height)
        # See the comment in the setter for IpcBorderWidth. The exact same thing applies for
        # IpcFrameWidth, except in this case the geometry from X11 perspective is actually impacted.
        let extents = [self.config.borderWidth, self.config.borderWidth,
        self.config.borderWidth+self.config.frameHeight,
        self.config.borderWidth]
        discard self.dpy.XChangeProperty(
          client.window,
          self.netAtoms[NetFrameExtents],
          XaCardinal,
          32,
          PropModeReplace,
          cast[cstring](unsafeAddr extents),
          4
        )
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextActivePixel]:
      log "Chaging text active pixel to " & $ev.data.l[1]
      self.config.textActivePixel = uint ev.data.l[1]
      if self.focused.isNone: return
      self.raiseClient self.clients[self.focused.get]
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextInactivePixel]:
      log "Chaging text inactive pixel to " & $ev.data.l[1]
      self.config.textInactivePixel = uint ev.data.l[1]
      if self.focused.isNone: return
      self.raiseClient self.clients[self.focused.get]
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextFont]:
      log "IpcTextFont"
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcTextFont])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing text font to " & $fontList[0]
      self.font = self.dpy.XftFontOpenName(XDefaultScreen self.dpy, fontList[0])
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcTextOffset]:
      log "Changing text offset to (x: " & $ev.data.l[1] & ", y: " & $ev.data.l[
          2] & ")"
      self.config.textOffset = (x: uint ev.data.l[1], y: uint ev.data.l[2])
      for client in self.clients.mitems: self.renderTop client
    elif ev.data.l[0] == clong self.ipcAtoms[IpcKillClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      discard self.dpy.XKillClient window
    elif ev.data.l[0] == clong self.ipcAtoms[IpcCloseClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      let cm = XEvent(xclient: XClientMessageEvent(format: 32,
        theType: ClientMessage, serial: 0, sendEvent: true, display: self.dpy,
        window: window, messageType: self.dpy.XInternAtom("WM_PROTOCOLS",
            false),
        data: XClientMessageData(l: [clong self.dpy.XInternAtom(
            "WM_DELETE_WINDOW", false), CurrentTime, 0, 0, 0])))
      discard self.dpy.XSendEvent(window, false, NoEventMask, cast[ptr XEvent](unsafeAddr cm))
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaximizeClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      var client: Client
      if self.focused.isSome:
        client = self.clients[self.focused.get]
      else:
        var co = self.findClient do (c: Client) -> bool: c.window == Window ev.data.l[1]
        if co.isNone: return
        client = (co.get)[0][]
      self.maximizeClient client
    elif ev.data.l[0] == clong self.ipcAtoms[IpcSwitchTag]:
      echo ev.data.l
      self.tags.switchTag uint8 ev.data.l[1] - 1
      self.updateTagState
      let numdesk = [ev.data.l[1] - 1]
      discard self.dpy.XChangeProperty(
        self.root,
        self.netAtoms[NetCurrentDesktop],
        XaCardinal,
        32,
        PropModeReplace,
        cast[cstring](unsafeAddr numdesk),
        1
      )
      discard self.dpy.XSetInputFocus(self.root, RevertToPointerRoot, CurrentTime)
      self.focused = none uint
      if self.clients.len == 0: return
      var lcot = -1
      for i, c in self.clients:
        if c.tags == self.tags: lcot = i
      if lcot == -1: return
      self.focused = some uint lcot
      discard self.dpy.XRaiseWindow self.clients[self.focused.get].frame.window
      discard self.dpy.XSetInputFocus(self.clients[self.focused.get].window, RevertToPointerRoot, CurrentTime)
      self.raiseClient self.clients[self.focused.get]
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcAddTag]:
      discard
    elif ev.data.l[0] == clong self.ipcAtoms[IpcRemoveTag]:
      discard
    elif ev.data.l[0] == clong self.ipcAtoms[IpcLayout]:
      # We recieve this IPC event when a client such as wormc wishes to change the layout (eg, floating -> tiling)
      if ev.data.l[1] notin {0, 1}: return
      self.layout = Layout ev.data.l[1]
      for i, _ in self.clients:
        self.clients[i].floating = self.layout == lyFloating
      log $self.clients
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcGaps]:
      self.config.gaps = int ev.data.l[1]
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaster]:
      # Get the index of the client, for swapping.
      # this isn't actually done yet
      let newMasterIdx = block:
        if ev.data.l[1] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[1]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      var
        currMasterOpt: Option[Client] = none Client
        currMasterIdx: uint = 0
      for i, client in self.clients:
        if client.tags == self.tags: # We only care about clients on the current tag.
          if currMasterOpt.isNone: # This must be the first client on the tag, otherwise master would not be nil; therefore, we promote it to master.
            currMasterOpt = some self.clients[i]
            currMasterIdx = uint i
      if currMasterOpt.isNone: return
      let currMaster = currMasterOpt.get
      self.clients[currMasterIdx] = self.clients[newMasterIdx]
      self.clients[newMasterIdx] = currMaster
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcStruts]:
      self.config.struts = (
        top: uint ev.data.l[1],
        bottom: uint ev.data.l[2],
        left: uint ev.data.l[3],
        right: uint ev.data.l[4]
      )
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMoveTag]: # [tag, wid | 0, 0, 0, 0]
      log $ev.data.l
      let tag = ev.data.l[1] - 1
      let client = block:
        if ev.data.l[2] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[2]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      self.clients[client].tags = [false, false, false, false, false, false,
          false, false, false]
      self.clients[client].tags[tag] = true
      self.updateTagState
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFloat]:
      let client = block:
        if ev.data.l[1] != 0:
          let clientOpt = self.findClient do (client: Client) ->
              bool: client.window == uint ev.data.l[1]
          if clientOpt.isNone: return
          clientOpt.get[1]
        else:
          if self.focused.isSome: self.focused.get else: return
      self.clients[client].floating = true
      if self.layout == lyTiling: self.tileWindows
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameLeft]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameLeft])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          of "I": fpMinimize
          else: continue
      self.config.frameParts.left = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameCenter]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameCenter])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          of "I": fpMinimize
          else: continue
      self.config.frameParts.center = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcFrameRight]:
      log "Frame Right"
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcFrameRight])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      if fontList == nil or fontList[0] == nil and err >= Success and n > 0: return
      let x = ($fontList[0]).split ";"
      var parts: seq[FramePart]
      for v in x:
        parts.add case v:
          of "T": fpTitle
          of "C": fpClose
          of "M": fpMaximize
          of "I": fpMinimize
          else: continue
      self.config.frameParts.right = parts
      log $self.config.frameParts
      XFreeStringList cast[ptr cstring](fontList)
    elif ev.data.l[0] == clong self.ipcAtoms[IpcButtonOffset]:
      self.config.buttonOffset = (
        x: uint ev.data.l[1],
        y: uint ev.data.l[2]
      )
      log $self.config.buttonOffset
    elif ev.data.l[0] == clong self.ipcAtoms[IpcButtonSize]:
      self.config.buttonSize = uint ev.data.l[1]
    elif ev.data.l[0] == clong self.ipcAtoms[IpcRootMenu]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcRootMenu])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing root menu path to " & $fontList[0]
      self.config.rootMenu = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcCloseActivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcCloseActivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing active close path to " & $fontList[0]
      self.config.closePaths[bsActive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcCloseInactivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcCloseInactivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing inactive close path to " & $fontList[0]
      self.config.closePaths[bsInactive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaximizeActivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcMaximizeActivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing active maximize path to " & $fontList[0]
      self.config.maximizePaths[bsActive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMaximizeInactivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcMaximizeInactivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing inactive maximize path to " & $fontList[0]
      self.config.maximizePaths[bsInactive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMinimizeActivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcMinimizeActivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing active minimize path to " & $fontList[0]
      self.config.minimizePaths[bsActive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMinimizeInactivePath]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcMinimizeInactivePath])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Changing inactive minimize path to " & $fontList[0]
      self.config.minimizePaths[bsInactive] = $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcDecorationDisable]:
      var fontProp: XTextProperty
      var fontList: ptr UncheckedArray[cstring]
      var n: cint
      discard self.dpy.XGetTextProperty(self.root, addr fontProp, self.ipcAtoms[
          IpcDecorationDisable])
      let err = self.dpy.XmbTextPropertyToTextList(addr fontProp, cast[
          ptr ptr cstring](addr fontList), addr n)
      log "Appending to decoration disable list: " & $fontList[0]
      self.noDecorList.add re $fontList[0]
      if err >= Success and n > 0 and fontList != nil and fontList[0] != nil:
        XFreeStringList cast[ptr cstring](fontList)
      discard XFree fontProp.value
    elif ev.data.l[0] == clong self.ipcAtoms[IpcMinimizeClient]:
      let window = if ev.data.l[1] == 0: self.clients[
          if self.focused.isSome: self.focused.get else: return].window else: Window ev.data.l[1]
      var client: Client
      if self.focused.isSome:
        client = self.clients[self.focused.get]
      else:
        var co = self.findClient do (c: Client) -> bool: c.window == Window ev.data.l[1]
        if co.isNone: return
        client = (co.get)[0][]
      self.minimizeClient client
