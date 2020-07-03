# To run these tests, simply execute `nimble test`.

import unittest

import genepkg/compiler

test "Compiler":
  check compile("nil") == @[instr_init()]
