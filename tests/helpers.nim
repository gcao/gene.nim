import unittest, strutils

import gene/types
import gene/parser
import gene/interpreter
import gene/arg_parser

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

proc test_parser*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    callback read(code)

proc test_parser_error*(code: string) =
  var code = cleanup(code)
  test "Parser error expected: " & code:
    try:
      discard read(code)
    except ParseError:
      discard

proc test_read_all*(code: string, result: seq[GeneValue]) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    check read_all(code) == result

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
    interpreter.load_core_module()
    interpreter.load_gene_module()
    interpreter.load_genex_module()
    check interpreter.eval(code) == result

proc test_core*(code: string, callback: proc(result: GeneValue)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    var app = new_app()
    var interpreter = new_vm(app)
    interpreter.load_core_module()
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

proc test_match*(pattern: string, input: string, callback: proc(result: MatchResult)) =
  var pattern = cleanup(pattern)
  var input = cleanup(input)
  test "Pattern Matching: \n" & pattern & "\n" & input:
    var p = read(pattern)
    var i = read(input)
    var m = new_match_matcher()
    m.parse(p)
    var result = m.match(i)
    callback(result)

proc test_import_matcher*(code: string, callback: proc(result: ImportMatcherRoot)) =
  var code = cleanup(code)
  test "Import: " & code:
    var v = read(code)
    var m = new_import_matcher(v)
    callback m

proc test_args*(schema, input: string, callback: proc(r: ArgMatchingResult)) =
  var schema = cleanup(schema)
  var input = cleanup(input)
  test schema & "\n" & input:
    var m = new_matcher()
    m.parse(schema)
    var r = m.match(input)
    callback r
