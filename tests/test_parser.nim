# To run these tests, simply execute `nimble test` or `nim c -r tests/test_parser.nim`

import unittest, options, tables, unicode

import gene/types
import gene/parser

import ./helpers

test_parser("nil", GeneNil)
test_parser("true", true)
test_parser("false", false)

test_parser("10", 10)
test_parser("10e10", 10e10)
test_parser("+5.0E5", +5.0E5)

test_parser("'t", 't')
test_parser("'\\t", '\t')
test_parser("'\\tab", '\t')
test_parser("'中", "中".runeAt(0))

test_parser("\"test\"", "test")

test_parser("a", new_gene_symbol("a"))
test_parser("A", new_gene_symbol("A"))
test_parser("n/A", new_gene_complex_symbol("n", @["A"]))
test_parser("n/m/A", new_gene_complex_symbol("n", @["m", "A"]))
test_parser("\\true", new_gene_symbol("true"))

test_parser("{}", Table[string, GeneValue]())
test_parser("{^a 1}", {"a": new_gene_int(1)}.toTable)

test_read_all """
  1 # comment
  2
""", proc(r: seq[GeneValue]) =
  check r[0] == 1
  check r[1] == 2

test "Parser":
  var node: GeneValue
  var nodes: seq[GeneValue]

  nodes = read_all("10 11")
  check nodes.len == 2
  check nodes[0].int == 10
  check nodes[1].int == 11

  node = read("1 2 3")
  check node.kind == GeneInt
  check node.int == 1

  node = read("(1 2 3)")
  check node.kind == GeneGene
  check node.gene.data.len == 2

  node = read("(1 ^a 1 2 3)")
  check node.kind == GeneGene
  check node.gene.props == {"a": new_gene_int(1)}.toTable
  check node.gene.data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 ^^a 2 3)")
  check node.kind == GeneGene
  check node.gene.props == {"a": GeneTrue}.toTable
  check node.gene.data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 ^!a 2 3)")
  check node.kind == GeneGene
  check node.gene.props == {"a": GeneFalse}.toTable
  check node.gene.data == @[new_gene_int(2), new_gene_int(3)]

  node = read("""
    (
      ;; comment in a list
    )
  """)
  check node.kind == GeneGene

  node = read("""
    {^^x ^!y ^^z}
  """)
  check node.kind == GeneMap
  check node.map == {"x": GeneTrue, "y": GeneFalse, "z": GeneTrue}.toTable

  node = read("1")
  check node.kind == GeneInt
  check node.int == 1

  node = read("-1")
  check node.kind == GeneInt
  check node.int == -1

  node = read("()")
  check node.gene.op == nil
  check node.kind == GeneGene
  check node.gene.data.len == 0

  node = read("(1)")
  check node.gene.op == GeneValue(kind: GeneInt, int: 1)
  check node.kind == GeneGene
  check node.gene.data.len == 0

  node = read("(())")
  check node.kind == GeneGene
  check node.gene.data.len == 0
  check node.gene.op.kind == GeneGene
  check node.gene.op.gene.data.len == 0

  node = read("nil")
  check node.kind == GeneNilKind

  node = read("symbol-👋") #emoji
  check node.kind == GeneSymbol
  check node.symbol == "symbol-👋"

  node = read("+foo+")
  check node.kind == GeneSymbol
  check node.symbol == "+foo+"

  # TODO
  # node = read("moo/bar")
  # check node.kind == GeneComplexSymbol
  # check node.csymbol == ("moo", "bar")

  node = read(":foo") # -> (quote foo)
  check node.kind == GeneGene
  check node.gene.op == new_gene_symbol("quote")

  node = read("{}")
  check node.kind == GeneMap
  check node.map.len == 0

  node = read("{^A 1 ^B 2}")
  check node.kind == GeneMap
  check node.map.len == 2

  node = read("{^A 1, ^B 2}")
  check node.kind == GeneMap
  check node.map.len == 2

  node = read("[1 2 , 3,4]")
  check node.kind == GeneVector
  check node.vec.len == 4

  node = read("\"foo\"")
  check node.kind == GeneString
  check node.str == "foo"
  check node.str.len == 3

  node = read("#_ [foo bar]")
  check node == nil

  node = read("1/2")
  check node.kind == GeneRatio
  check node.ratio == (BiggestInt(1), BiggestInt(2))

  node = read("{^ratio -1/2}")
  check node.kind == GeneMap
  check node.map["ratio"] == new_gene_ratio(-1, 2)

  # let's set up conditional forms reading
  var opts: ParseOptions
  init_gene_readers(opts)

  var opts1: ParseOptions
  opts1.eof_is_error = true
  opts1.suppress_read = false

  try:
    node = read("{^ratio 1/-2}")
    check node.kind == GeneMap
  except ParseError:
    discard

  try:
    node = read(";; foo bar")
    check false
  except ParseError:
    discard

  node = read("#\".*\"")
  check node.kind == GeneRegex

# TODO
# test "Parse document":
#   var doc: GeneDocument
#   doc = read_document("1 2 3")
