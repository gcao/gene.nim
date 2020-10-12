import unittest, strutils

import gene/types
import gene/parser
import gene/interpreter

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

proc cleanup*(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

proc test_parser*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_interpreter*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var interpreter = new_vm()
    check interpreter.eval(code) == result

proc test_interpreter*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var interpreter = new_vm()
    callback interpreter.eval(code)

proc test_core*(code: string, result: GeneValue) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var app = new_app()
    var interpreter = new_vm(app)
    # interpreter.load_core_module()
    interpreter.load_gene_module()
    interpreter.load_genex_module()
    check interpreter.eval(code) == result

proc test_core*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var app = new_app()
    var interpreter = new_vm(app)
    # interpreter.load_core_module()
    interpreter.load_gene_module()
    interpreter.load_genex_module()
    callback interpreter.eval(code)
