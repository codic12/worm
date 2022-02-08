import
  wm,
  events

when isMainModule:
  var instance = initWm()
  instance.eventLoop()
