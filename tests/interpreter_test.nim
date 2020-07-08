# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/vm_types
import gene/interpreter

test "Interpreter = VM.eval()":
  var vm = new_vm()
  check vm.eval("nil") == GeneNil

  vm = new_vm()
  check vm.eval("1") == new_gene_int(1)

  vm = new_vm()
  check vm.eval("true") == GeneTrue

  vm = new_vm()
  check vm.eval("1 2 3") == new_gene_int(3)

  vm = new_vm()
  check vm.eval("(1 + 2)") == new_gene_int(3)

  vm = new_vm()
  check vm.eval("(3 - 2)") == new_gene_int(1)

  vm = new_vm()
  check vm.eval("(1 == 1)") == GeneTrue

  vm = new_vm()
  check vm.eval("(1 < 1)") == GeneFalse

  vm = new_vm()
  check vm.eval("(1 <= 1)") == GeneTrue

  vm = new_vm()
  check vm.eval("(var a 1) a") == new_gene_int(1)

  vm = new_vm()
  check vm.eval("(var a 1) (a = 2) a") == new_gene_int(2)

  vm = new_vm()
  check vm.eval("(var a) (a = 2) a") == new_gene_int(2)

  vm = new_vm()
  check vm.eval("(if true 1)") == new_gene_int(1)

  vm = new_vm()
  check vm.eval("(if false 1 else 2)") == new_gene_int(2)

  vm = new_vm()
  check vm.eval("""
    (if false 1
      elif true 2
      else 3
    )
  """) == new_gene_int(2)

  vm = new_vm()
  check vm.eval("(fn f [] 1) (f)") == new_gene_int(1)

  vm = new_vm()
  check vm.eval("(fn f a (a + 1)) (f 1)") == new_gene_int(2)

  vm = new_vm()
  check vm.eval("""
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib 6)
  """) == new_gene_int(2)
