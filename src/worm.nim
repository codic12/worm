import
  std/[os, osproc, parseopt],
  wm,
  events,
  log

when isMainModule:
  var instance = initWm()

  var rcFile = "~/.config/worm/rc"

  var p = initOptParser("")
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption:
      case p.key
      of "rcfile":
        rcFile = p.val
      else: discard
    else: discard

  if fileExists expandTilde rcFile:
    log "config file found, loading..."
    discard startProcess expandTilde rcFile
    log "config file loaded!"

  instance.eventLoop()
