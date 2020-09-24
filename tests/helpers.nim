import unittest, strutils

import gene/types
import gene/parser
import gene/interpreter
import gene/interpreter2
import gene/compiler
import gene/vm
import gene/cpu

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

proc cleanup(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

proc test_parser*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_eval*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var vm = new_vm()
    check vm.eval(code) == result

proc test_eval*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var vm = new_vm()
    callback vm.eval(code)

proc test_compiler*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Compiler / VM: " & code:
    var c = new_compiler()
    var vm = new_vm()
    var module = c.compile(code)
    check vm.run(module) == result

proc test_compiler*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Compiler / VM: " & code:
    var c = new_compiler()
    var vm = new_vm()
    var module = c.compile(code)
    callback vm.run(module)

proc test_interpreter*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Interpreter2 / eval: " & code:
    var interpreter = new_interpreter2()
    check interpreter.eval(code) == result

proc test_interpreter*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Interpreter2 / eval: " & code:
    var interpreter = new_interpreter2()
    callback interpreter.eval(code)
