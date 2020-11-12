# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "An example application in Gene language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @[]

# Dependencies

requires "nim >= 1.0.0"

task build-ext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:. src/my_ext.nim"
