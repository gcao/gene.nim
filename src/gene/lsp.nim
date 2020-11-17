import streams, strutils, parseutils, json

include lsppkg/messages

type
  BaseProtocolError* = object of Defect

  MalformedFrame* = object of BaseProtocolError
  UnsupportedEncoding* = object of BaseProtocolError

proc skipWhitespace(x: string, pos: int): int =
  result = pos
  while result < x.len and x[result] in Whitespace:
    inc result

proc sendFrame*(s: Stream, frame: string) =
  when defined(debugCommunication):
    stderr.write(frame)
    stderr.write("\n")
  s.write "Content-Length: " & $frame.len & "\r\n\r\n" & frame
  s.flush

proc sendJson*(s: Stream, data: JsonNode) =
  var frame = newStringOfCap(1024)
  toUgly(frame, data)
  s.sendFrame(frame)

proc readFrame*(s: Stream): TaintedString =
  var contentLen = -1
  var headerStarted = false

  while true:
    var ln = string s.readLine()

    if ln.len != 0:
      headerStarted = true
      let sep = ln.find(':')
      if sep == -1:
        raise newException(MalformedFrame, "invalid header line: " & ln)

      let valueStart = ln.skipWhitespace(sep + 1)

      case ln[0 ..< sep]
      of "Content-Type":
        if ln.find("utf-8", valueStart) == -1 and ln.find("utf8", valueStart) == -1:
          raise newException(UnsupportedEncoding, "only utf-8 is supported")
      of "Content-Length":
        if parseInt(ln, contentLen, valueStart) == 0:
          raise newException(MalformedFrame, "invalid Content-Length: " &
                                              ln.substr(valueStart))
      else:
        # Unrecognized headers are ignored
        discard
    elif not headerStarted:
      continue
    else:
      if contentLen != -1:
        when defined(debugCommunication):
          let msg = s.readStr(contentLen)
          stderr.write(msg)
          stderr.write("\n")
          return msg
        else:
          return s.readStr(contentLen)
      else:
        raise newException(MalformedFrame, "missing Content-Length header")

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
        discard
  except IOError:
    break
  except CatchableError as e:
    debugEcho "Got exception: ", e.msg
    continue
