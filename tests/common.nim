import unittest

import gene/types
import gene/compiler
import gene/vm
import gene/cpu

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

proc test_compiler*(code: string, result: GeneValue) =
  test "Compiler / VM: " & code:
    var c = new_compiler()
    var vm = new_vm()
    var module = c.compile(code)
    check vm.run(module) == result