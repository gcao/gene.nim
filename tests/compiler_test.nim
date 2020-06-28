# To run these tests, simply execute `nimble test`.

import unittest
import genepkg/parser, genepkg/compiler, options, tables, strutils

test "Compiler":
  var node: GeneNode

  node = read("nil")
