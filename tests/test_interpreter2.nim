import unittest

import gene/types
import gene/interpreter2

import ./helpers

proc test_interpreter*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    init_all()
    check VM.eval(code) == result

test_interpreter "nil", GeneNil
