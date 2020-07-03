# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/interpreter

test "Interpreter":
  var i = Interpreter()
  check i.eval("nil") == Nil
