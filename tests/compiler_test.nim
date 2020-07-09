# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/compiler
import gene/vm_types
import gene/interpreter

test "Compiler / VM":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("nil")
  check vm.eval(module) == GeneNil
