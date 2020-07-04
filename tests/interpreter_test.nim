# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/vm_types
import gene/interpreter

test "Interpreter = VM.eval()":
  var vm = VM()
  check vm.eval("nil") == GeneNil

  vm = VM()
  check vm.eval("1") == new_gene_int(1)

  vm = VM()
  check vm.eval("1 2 3") == new_gene_int(3)

  vm = VM()
  check vm.eval("(var a 1) a") == new_gene_int(1)
