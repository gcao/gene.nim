# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "A test application in Gene language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["test"]

# Dependencies

requires "nim >= 1.0.0"

task buildext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:. src/test_ext.nim"