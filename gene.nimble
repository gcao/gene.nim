# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "Gene - a general purpose language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["gene"]

# Dependencies

requires "nim >= 1.0.0"
requires "jsonschema >= 0.2.1"

task buildext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:tests tests/extension.nim"

before test:
  exec "nim c --app:lib --outdir:tests tests/extension.nim"
