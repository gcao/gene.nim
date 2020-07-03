# To run these tests, simply execute `nimble test`.

import unittest

import genepkg/types
import genepkg/interpreter

test "Interpreter":
  var i = Interpreter()
  check i.interpret("nil") == Nil
