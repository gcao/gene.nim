# To run these tests, simply execute `nimble test` or `nim c -r tests/test_parser.nim`

import unittest, options, tables, strutils

import gene/types
import gene/parser
import ./helpers

test_parser("nil", GeneNil)
test_parser("10", 10)
test_parser("10e10", 10e10)
test_parser("+5.0E5", +5.0E5)
test_parser("true", true)
test_parser("false", false)
test_parser("\"test\"", "test")

test_parser("A", new_gene_symbol("A"))
test_parser("n/A", new_gene_complex_symbol("n", @["A"]))
test_parser("n/m/A", new_gene_complex_symbol("n", @["m", "A"]))

test_parser("{}", Table[string, GeneValue]())
test_parser("{:a 1}", {"a": new_gene_int(1)}.toTable)

test "Parser":
  var node: GeneValue
  var nodes: seq[GeneValue]

  nodes = read_all("10 11")
  check nodes.len == 2
  check nodes[0].d.num == 10
  check nodes[1].d.num == 11

  node = read("1 2 3")
  check node.d.kind == GeneInt
  check node.d.num == 1

  node = read("(1 2 3)")
  check node.d.kind == GeneGene
  check node.d.gene_data.len == 2

  node = read("(1 :a 1 2 3)")
  check node.d.kind == GeneGene
  check node.d.gene_props == {"a": new_gene_int(1)}.toTable
  check node.d.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 ::a 2 3)")
  check node.d.kind == GeneGene
  check node.d.gene_props == {"a": GeneTrue}.toTable
  check node.d.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 :!a 2 3)")
  check node.d.kind == GeneGene
  check node.d.gene_props == {"a": GeneFalse}.toTable
  check node.d.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("""
    (
      ;; comment in a list
    )
  """)
  check node.d.kind == GeneGene
  # check node.d.comments.len == 0

  block:
    # comment related tests

    var opts: ParseOptions
    opts.eof_is_error = true
    opts.suppress_read = false
    opts.comments_handling = keepComments
    node = read("""
      ;; this is a comment
      ()
    """, opts)
    check node.d.kind == GeneCommentLine
    # check node.comments.len == 0

    node = read("""
      #!/usr/bin/env gene
      ()
    """, opts)
    check node.d.kind == GeneCommentLine
    # check node.d.comments.len == 0

    # node = read("""
    #   (
    #     ;; this is a comment
    #   ())
    # """, opts)
    # check node.d.kind == GeneGene
    # check node.d.gene_op.comments.len > 0

    # node = read("""
    #   ;; this is a comment
    #   (1 2
    #     ;; last elem
    #   3)
    # """, opts)
    # check node.d.kind == GeneCommentLine

    # # the comment should be returned on subsequent read().
    # # not very clean, but does not require a look-ahead read()
    # node = read("""
    #   ()
    #   ;; comment after a list
    # """, opts)
    # check node.d.kind == GeneGene
    # check node.d.comments.len == 0

    # node = read("""
    #   (
    #     ;; comment in a list
    #   )
    # """, opts)
    # check node.d.kind == GeneGene
    # check node.d.comments.len == 1
    # check node.d.comments[0].placement == Inside

    # node = read("""
    #   ;; this is a comment
    #   (1 2
    #     ;; last elem
    #   3)
    # """, opts)
    # check node.d.kind == GeneCommentLine
    # check node.d.comments.len == 0

    node = read("""
      {:x 1
      ;;comment
      :y 2}
    """, opts)
    check node.d.kind == GeneMap
    check node.d.map == {"x": new_gene_int(1), "y": new_gene_int(2)}.toTable

    node = read("""
      {::x :!y ::z}
    """, opts)
    check node.d.kind == GeneMap
    check node.d.map == {"x": GeneTrue, "y": GeneFalse, "z": GeneTrue}.toTable

  #   node = read("""
  #     {:view s/Keyword
  #     ;;comment
  #     (s/optional-key :label 1) s/Str
  #     (foo 1) 2}
  #   """, opts)
  #   check node.d.kind == GeneMap


  # node = read("""
  #   {:view s/Keyword
  #     ;;comment
  #     (s/optional-key :label 1) s/Str
  #     (foo 1) 2
  #   }
  # """)
  # check node.d.kind == GeneMap

  node = read("""
    ;; this is a comment
    (1 2
      ;; last elem
    3)
  """)
  check node.d.kind == GeneGene
  # check node.d.comments.len == 0
  # check node.d.gene_data[1].comments.len == 0

  node = read("1")
  check node.d.kind == GeneInt
  check node.d.num == 1

  node = read("-1")
  check node.d.kind == GeneInt
  check node.d.num == -1

  node = read("()")
  check node.d.gene_op.d == nil
  check node.d.kind == GeneGene
  check node.d.gene_data.len == 0

  node = read("(1)")
  check node.d.gene_op == new_gene_int(1)
  check node.d.kind == GeneGene
  check node.d.gene_data.len == 0

  node = read("(())")
  check node.d.kind == GeneGene
  check node.d.gene_data.len == 0
  check node.d.gene_op.d.kind == GeneGene
  check node.d.gene_op.d.gene_data.len == 0

  node = read("nil")
  check node.d.kind == GeneNilKind

  node = read("symbol-👋") #emoji
  check node.d.kind == GeneSymbol
  check node.d.symbol == "symbol-👋"

  # node = read(":foo")
  # check node.kind == GeneKeyword
  # check node.keyword.name == "foo"
  # check node.is_namespaced == false
  # check $node == ":foo"

  # node = read("::foobar")
  # check node.kind == GeneKeyword
  # check node.keyword.name == "foobar"
  # check node.keyword.ns == ""
  # check node.is_namespaced == true
  # check $node == "::foobar"

  node = read("+foo+")
  check node.d.kind == GeneSymbol
  check node.d.symbol == "+foo+"

  # TODO
  # node = read("moo/bar")
  # check node.kind == GeneComplexSymbol
  # check node.csymbol == ("moo", "bar")

  node = read("'foo") # -> (quote foo)
  check node.d.kind == GeneGene
  check node.d.gene_op == new_gene_symbol("quote")

  node = read("{}")
  check node.d.kind == GeneMap
  check node.d.map.len == 0

  node = read("{:A 1 :B 2}")
  check node.d.kind == GeneMap
  check node.d.map.len == 2

  node = read("{:A 1, :B 2}")
  check node.d.kind == GeneMap
  check node.d.map.len == 2

  # try:
  #   node = read("moo/bar/baz")
  #   raise new_exception(Exception, "FAILURE")
  # except ParseError:
  #   discard

  node = read("[1 2 , 3,4]")
  check node.d.kind == GeneVector
  check node.d.vec.len == 4

  let hh = new_hmap()
  hh[new_gene_keyword("", "foo")] = GeneTrue
  check hh[new_gene_keyword("", "foo")].get() == new_gene_bool(true)

  node = read("\"foo\"")
  check node.d.kind == GeneString
  check node.d.str == "foo"
  check node.d.str.len == 3

  node = read("#_ [foo bar]")
  check node.d == nil

  node = read("#[foo whateve 1]")
  check node.d.kind == GeneSet
  check node.d.set_elems.count == 3

  node = read("#[]")
  check node.d.kind == GeneSet
  check node.d.set_elems.count == 0

  node = read("1/2")
  check node.d.kind == GeneRatio
  check node.d.rnum == (BiggestInt(1), BiggestInt(2))

  node = read("{:ratio -1/2}")
  check node.d.kind == GeneMap
  check node.d.map["ratio"] == new_gene_ratio(-1, 2)

  # let's set up conditional forms reading
  var opts: ParseOptions
  init_gene_readers(opts)

  var opts1: ParseOptions
  opts1.eof_is_error = true
  opts1.suppress_read = false

  try:
    node = read("{:ratio 1/-2}")
    check node.d.kind == GeneMap
  except ParseError:
    discard

  try:
    node = read(";; foo bar")
    check false
  except ParseError:
    discard

  node = read("()") # for the following to work
  var n1: GeneValue = GeneNil
  var n2: GeneValue = GeneNil
  var n3: GeneValue = GeneFalse
  var n4: GeneValue = GeneFalse
  #echo "===? ", n1 == n2
  var t = new_table[GeneValue,int]()
  t[n3] = 3
  #echo "COUNT OF ELEMS ", t.len, " ", n1.hash, " ", n2.hash, " ", n3.hash
  t[n4] = 4
  #echo "COUNT OF ELEMS ", t.len, " ", n1.hash, " ", n2.hash, " ", n3.hash
  t[n4] = 5
  #echo "COUNT OF ELEMS ", t.len, " ", n1.hash, " ", n2.hash, " ", n3.hash

  var mm1 = new_hmap()
  mm1[n2] = n2
  mm1[node] = node

  mm1 = new_hmap(0)
  mm1[node] = node
  check mm1.count == 1
  mm1[n1] = n1
  check mm1.count == 2
  mm1[n1] = n2
  check mm1.count == 2
  for i in 1..10:
    mm1[new_gene_int(i.int_to_str())] = new_gene_int(i.int_to_str())
  check mm1.count == 12
  check mm1[n1].get() == n2

  node = read("#\".*\"")
  check node.d.kind == GeneRegex

  #check add(5, 5) == 10

# TODO
# test "Parse document":
#   var doc: GeneDocument
#   doc = read_document("1 2 3")
