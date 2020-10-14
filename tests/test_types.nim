# To run these tests, simply execute `nimble test` or `nim c -r tests/test_types.nim`

import unittest

import gene/types
import gene/parser

import ./helpers

test "GeneAny":
  var s = "abc"
  var g = GeneValue(
    kind: GeneAny,
    any: cast[pointer](s.addr),
  )
  check cast[ptr string](g.any)[] == s

proc test_normalize(code: string, r: GeneValue) =
  var code = cleanup(code)
  test "normalize: " & code:
    var parsed = read(code)
    parsed.normalize
    check parsed == r

test_normalize("(1 + 2)", read("(+ 1 2)"))

test_normalize("(.@test)", read("(@ \"test\")"))
test_normalize("(self .@test)", read("(@ ^self self \"test\")"))
test_normalize("(@test = 1)", read("(@= \"test\" 1)"))
