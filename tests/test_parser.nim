# To run these tests, simply execute `nimble test`.

import unittest, options, tables, strutils

import gene/parser
import gene/types

test "Parser":
  var node: GeneValue
  var nodes: seq[GeneValue]

  node = read("nil")
  check node.kind == GeneNilKind

  node = read("10")
  check node.kind == GeneInt
  check node.num == 10

  nodes = read_all("10 11")
  check nodes.len == 2
  check nodes[0].num == 10
  check nodes[1].num == 11

  node = read("10e10")
  check node.kind == GeneFloat
  check node.fnum == 10e10

  node = read("+5.0E5")
  check node.kind == GeneFloat
  check node.fnum == +5.0E5

  node = read("true")
  check node.kind == GeneBool
  check node.boolVal == true

  node = read("1 2 3")
  check node.kind == GeneInt
  check node.num == 1

  node = read("(1 2 3)")
  check node.kind == GeneGene
  check node.gene_data.len == 2

  node = read("(1 :a 1 2 3)")
  check node.kind == GeneGene
  check node.gene_props == {"a": new_gene_int(1)}.toTable
  check node.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 ::a 2 3)")
  check node.kind == GeneGene
  check node.gene_props == {"a": GeneTrue}.toTable
  check node.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("(1 :!a 2 3)")
  check node.kind == GeneGene
  check node.gene_props == {"a": GeneFalse}.toTable
  check node.gene_data == @[new_gene_int(2), new_gene_int(3)]

  node = read("""
    (
      ;; comment in a list
    )
  """)
  check node.kind == GeneGene
  check node.comments.len == 0

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
    check node.kind == GeneCommentLine
    check node.comments.len == 0

    node = read("""
      #!/usr/bin/env gene
      ()
    """, opts)
    check node.kind == GeneCommentLine
    check node.comments.len == 0

    node = read("""
      (
        ;; this is a comment
      ())
    """, opts)
    check node.kind == GeneGene
    check node.gene_op.comments.len > 0

    node = read("""
      ;; this is a comment
      (1 2
        ;; last elem
      3)
    """, opts)
    check node.kind == GeneCommentLine

    # the comment should be returned on subsequent read().
    # not very clean, but does not require a look-ahead read()
    node = read("""
      ()
      ;; comment after a list
    """, opts)
    check node.kind == GeneGene
    check node.comments.len == 0

    # node = read("""
    #   (
    #     ;; comment in a list
    #   )
    # """, opts)
    # check node.kind == GeneGene
    # check node.comments.len == 1
    # check node.comments[0].placement == Inside

    node = read("""
      ;; this is a comment
      (1 2
        ;; last elem
      3)
    """, opts)
    check node.kind == GeneCommentLine
    check node.comments.len == 0

    node = read("""
      {:x 1
      ;;comment
      :y 2}
    """, opts)
    check node.kind == GeneMap
    check node.map == {"x": new_gene_int(1), "y": new_gene_int(2)}.toTable

    node = read("""
      {::x :!y ::z}
    """, opts)
    check node.kind == GeneMap
    check node.map == {"x": GeneTrue, "y": GeneFalse, "z": GeneTrue}.toTable

  #   node = read("""
  #     {:view s/Keyword
  #     ;;comment
  #     (s/optional-key :label 1) s/Str
  #     (foo 1) 2}
  #   """, opts)
  #   check node.kind == GeneMap


  # node = read("""
  #   {:view s/Keyword
  #     ;;comment
  #     (s/optional-key :label 1) s/Str
  #     (foo 1) 2
  #   }
  # """)
  # check node.kind == GeneMap

  node = read("""
    ;; this is a comment
    (1 2
      ;; last elem
    3)
  """)
  check node.kind == GeneGene
  check node.comments.len == 0
  check node.gene_data[1].comments.len == 0

  node = read("1")
  check node.kind == GeneInt
  check node.num == 1

  node = read("-1")
  check node.kind == GeneInt
  check node.num == -1

  node = read("()")
  check node.gene_op == nil
  check node.kind == GeneGene
  check node.gene_data.len == 0

  node = read("(1)")
  check node.gene_op == GeneValue(kind: GeneInt, num: 1)
  check node.kind == GeneGene
  check node.gene_data.len == 0

  node = read("(())")
  check node.kind == GeneGene
  check node.gene_data.len == 0
  check node.gene_op.kind == GeneGene
  check node.gene_op.gene_data.len == 0

  node = read("nil")
  check node.kind == GeneNilKind

  node = read("symbol-👋") #emoji
  check node.kind == GeneSymbol
  check node.symbol == "symbol-👋"

  node = read(":foo")
  check node.kind == GeneKeyword
  check node.keyword.name == "foo"
  check node.is_namespaced == false
  check $node == ":foo"

  node = read("::foobar")
  check node.kind == GeneKeyword
  check node.keyword.name == "foobar"
  check node.keyword.ns == ""
  check node.is_namespaced == true
  check $node == "::foobar"

  node = read("+foo+")
  check node.kind == GeneSymbol
  check node.symbol == "+foo+"

  # TODO
  # node = read("moo/bar")
  # check node.kind == GeneComplexSymbol
  # check node.csymbol == ("moo", "bar")

  node = read("'foo") # -> (quote foo)
  check node.kind == GeneGene
  check node.gene_op == new_gene_symbol("quote")

  node = read("{}")
  check node.kind == GeneMap
  check node.map.len == 0

  node = read("{:A 1 :B 2}")
  check node.kind == GeneMap
  check node.map.len == 2

  node = read("{:A 1, :B 2}")
  check node.kind == GeneMap
  check node.map.len == 2

  try:
    node = read("moo/bar/baz")
    raise new_exception(Exception, "FAILURE")
  except ParseError:
    discard

  node = read("[1 2 , 3,4]")
  check node.kind == GeneVector
  check node.vec.len == 4

  let hh = new_hmap()
  hh[new_gene_keyword("", "foo")] = GeneTrue
  check hh[new_gene_keyword("", "foo")].get() == new_gene_bool(true)

  node = read("\"foo\"")
  check node.kind == GeneString
  check node.str == "foo"
  check node.str.len == 3

  node = read("#_ [foo bar]")
  check node == nil

  node = read("#[foo whateve 1]")
  check node.kind == GeneSet
  check node.set_elems.count == 3

  node = read("#[]")
  check node.kind == GeneSet
  check node.set_elems.count == 0

  node = read("1/2")
  check node.kind == GeneRatio
  check node.rnum == (BiggestInt(1), BiggestInt(2))

  node = read("{:ratio -1/2}")
  check node.kind == GeneMap
  check node.map["ratio"] == new_gene_ratio(-1, 2)

  # let's set up conditional forms reading
  var opts: ParseOptions
  init_gene_readers(opts)

  var opts1: ParseOptions
  opts1.eof_is_error = true
  opts1.suppress_read = false

  try:
    node = read("{:ratio 1/-2}")
    check node.kind == GeneMap
  except ParseError:
    discard

  try:
    node = read(";; foo bar")
    check false
  except ParseError:
    discard

  node = read("()") # for the following to work
  var n1: GeneValue = GeneValue(kind: GeneNilKind)
  var n2: GeneValue = GeneValue(kind: GeneNilKind)
  var n3: GeneValue = GeneValue(kind: GeneBool, boolVal: false)
  var n4: GeneValue = GeneValue(kind: GeneBool, boolVal: false)
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
  check node.kind == GeneRegex

  #check add(5, 5) == 10

# TODO
# test "Parse document":
#   var doc: GeneDocument
#   doc = read_document("1 2 3")
