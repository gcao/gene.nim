import asynchttpserver, asyncdispatch

# HTTP Server
# https://nim-lang.org/docs/asynchttpserver.html

proc handler(req: Request) {.async.} =
  let headers = {"Content-type": "text/plain; charset=utf-8"}
  await req.respond(Http200, "Hello World", headers.new_http_headers())

proc create_http_server*(port: int) =
  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

when isMainModule:
  create_http_server(2080)
  run_forever()
