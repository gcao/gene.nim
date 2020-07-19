import unittest, strutils

import gene/types
import gene/parser
import gene/interpreter
import gene/compiler
import gene/vm
import gene/cpu

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

proc test_parser*(code: string, result: GeneValue) =
  var code = code
  if code.contains("\n"):
    code = "\n" & code
  test "Parser / read: " & code:
    check read(code) == result

proc test_eval*(code: string, result: GeneValue) =
  var code = code
  if code.contains("\n"):
    code = "\n" & code
  test "Interpreter / eval: " & code:
    var vm = new_vm()
    check vm.eval(code) == result

proc test_compiler*(code: string, result: GeneValue) =
  var code = code
  if code.contains("\n"):
    code = "\n" & code
  test "Compiler / VM: " & code:
    var c = new_compiler()
    var vm = new_vm()
    var module = c.compile(code)
    check vm.run(module) == result