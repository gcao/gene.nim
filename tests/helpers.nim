import unittest, strutils

import gene/types
import gene/parser
import gene/interpreter
import gene/pattern_matching

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

proc test_read_all*(code: string, callback: proc(result: seq[GeneValue])) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    callback read_all(code)

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

proc test_arg_matching*(pattern: string, input: string, callback: proc(result: MatchResult)) =
  var pattern = cleanup(pattern)
  var input = cleanup(input)
  test "Pattern Matching: \n" & pattern & "\n" & input:
    var p = read(pattern)
    var i = read(input)
    var m = new_arg_matcher()
    m.parse(p)
    var result = m.match(i)
    callback(result)
