import streams, strutils, parseutils, json

include lsppkg/baseprotocol
include lsppkg/messages

var
  ins = newFileStream(stdin)
  outs = newFileStream(stdout)
  initialized = false

when defined(debugLogging):
  var logFile = open(get_env("HOME") & "/temp/gene/lsp.log", fmWrite)

template debugEcho(args: varargs[string, `$`]) =
  when defined(debugLogging):
    stderr.write(join args)
    stderr.write("\n")
    logFile.write(join args)
    logFile.write("\n\n")
    logFile.flushFile()

proc parseId(node: JsonNode): int =
  if node.kind == JString:
    parseInt(node.getStr)
  elif node.kind == JInt:
    node.getInt
  else:
    raise newException(MalformedFrame, "Invalid id node: " & repr(node))

proc respond(request: RequestMessage, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), some(data), none(ResponseError)).JsonNode

proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

proc notify(notification: string, data: JsonNode) =
  outs.sendJson create(NotificationMessage, "2.0", notification, some(data)).JsonNode

while true:
  try:
    let frame = ins.readFrame
    debugEcho "Got frame:\n" & frame
    let message = frame.parseJson
    debugEcho "Got valid Request message of type " & message["method"].getStr
    if not initialized and message["method"].getStr != "initialize":
      message.error(-32002, "Unable to accept requests before being initialized", newJNull())
      continue
    case message["method"].getStr:
      of "initialize":
        initialized = true
  except IOError:
    break
  except CatchableError as e:
    debugEcho "Got exception: ", e.msg
    continue
