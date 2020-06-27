# To run these tests, simply execute `nimble test`.

import unittest
import genepkg/parser, options, tables, strutils

# need to re-structure this at some point
test "everything":
  var node: GeneNode

  node = read("nil")
  check node.kind == GeneNil

  node = read("10")
  check node.kind == GeneInt
  check node.num == 10

  node = read("10e10")
  check node.kind == GeneFloat
  check node.fnum == 10e10

  node = read("+5.0E5")
  check node.kind == GeneFloat
  check node.fnum == +5.0E5

  node = read("true")
  check node.kind == GeneBool
  check node.boolVal == true
