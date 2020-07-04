# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/interpreter

test "Interpreter":
  var i = Interpreter()
  check i.eval("nil") == gene_nil

  i = Interpreter()
  check i.eval("1") == new_gene_int(1)
