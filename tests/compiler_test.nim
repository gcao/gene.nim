# To run these tests, simply execute `nimble test`.

import unittest

import gene/compiler

test "Compiler":
  var c = Compiler()
  check c.compile("nil") == @[instr_init()]
