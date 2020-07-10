# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/compiler
import gene/vm
import gene/interpreter

test "Compiler / VM":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("1")
  check vm.eval(module) == new_gene_int(1)

# (1 + 2) =>
# Save R0 1
# Save R1 2
# Add R0 R1 == Add R0 and R1 and save result in R0, release R1
#              This is like stack-based vm ?!

# (a + (b * c))
# GetMember R0 "a"
# GetMember R1 "b"
# GetMember R2 "c"
# Mul R1 R2
# Add R0 R1