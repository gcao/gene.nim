import asynchttpserver, asyncdispatch

# HTTP Server
# https://nim-lang.org/docs/asynchttpserver.html
# https://dev.to/xflywind/write-a-simple-web-framework-in-nim-language-from-scratch-ma0

proc create_http_server*(port: int, handler: proc(req: Request) {.async gcsafe.}) =
  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

when isMainModule:
  proc handler(req: Request) {.async.} =
    let headers = {"Content-type": "text/plain; charset=utf-8"}
    await req.respond(Http200, "Hello World", headers.new_http_headers())

  create_http_server(2080, handler)
  run_forever()
