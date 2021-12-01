import std/logging

var logger = newConsoleLogger(fmtStr = "$time | $levelname | ")
logger.addHandler

template log*(lvl: Level, data: string): untyped =
  let pos = instantiationInfo()
  let addition = "" & pos.filename & ":" & $pos.line & " | " # % [pos.filename, $pos.line]
  logger.log(lvl, addition & data)

template log*(data: string): untyped = log(lvlInfo, data)
