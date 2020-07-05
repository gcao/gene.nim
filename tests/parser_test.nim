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
  check node.list.len == 2

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
    opts.conditional_exprs = asError
    opts.comments_handling = keepComments
    node = read("""
      ;; this is a coment
      ()
    """, opts)
    check node.kind == GeneCommentLine
    check node.comments.len == 0

    node = read("""
      (
        ;; this is a coment
      ())
    """, opts)
    check node.kind == GeneGene
    check node.op.comments.len > 0

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

    node = read("""
      {:view s/Keyword
      ;;comment
      (s/optional-key :label) s/Str
      (foo 1) 2}
    """, opts)
    check node.kind == GeneMap


  node = read("""
    {:view s/Keyword
      ;;comment
      (s/optional-key :label) s/Str
      (foo 1) 2
    }
  """)
  check node.kind == GeneMap

  node = read("""
    ;; this is a comment
    (1 2
      ;; last elem
    3)
  """)
  check node.kind == GeneGene
  check node.comments.len == 0
  check node.list[1].comments.len == 0

  node = read("1")
  check node.kind == GeneInt
  check node.num == 1

  node = read("-1")
  check node.kind == GeneInt
  check node.num == -1

  node = read("()")
  check node.op == nil
  check node.kind == GeneGene
  check node.list.len == 0

  node = read("(1)")
  check node.op == GeneValue(kind: GeneInt, num: 1)
  check node.kind == GeneGene
  check node.list.len == 0

  node = read("(())")
  check node.kind == GeneGene
  check node.list.len == 0
  check node.op.kind == GeneGene
  check node.op.list.len == 0

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
  check node.op == new_gene_symbol("quote")

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

  node = read("^{:k 1} {}")
  check node.kind == GeneMap
  check node.map.count == 0
  # TODO: define 'len' for HMap
  check node.map_meta.count == 1
  check node.map_meta[new_gene_keyword("", "k")].get() == new_gene_int(1)

  let hh = new_hmap()
  hh[new_gene_keyword("", "foo")] = gene_true
  check hh[new_gene_keyword("", "foo")].get() == new_gene_bool(true)

  node = read("^ :foo []")
  check node.kind == GeneVector
  check node.vec.len == 0
  check node.vec_meta.count == 1
  check node.vec_meta[new_gene_keyword("", "foo")].get() == new_gene_bool(true)

  # TODO
  # node = read("^foo (1 2 3)")
  # check node.kind == GeneGene
  # check node.list.len == 2
  # check node.list_meta.count == 1
  # check node.list_meta[KeyTag].get() == new_gene_complex_symbol("", "foo")

  node = read("^\"foo\" Symbol")
  check node.kind == GeneSymbol
  check node.symbol == new_gene_symbol("Symbol").symbol
  check node.symbol_meta[KeyTag].get().kind == GeneString
  check node.symbol_meta[KeyTag].get().str == "foo"

  node = read("\"foo\"")
  check node.kind == GeneString
  check node.str == "foo"
  check node.str.len == 3

  node = read("#_ [foo bar]")
  check node == nil

  node = read("#{foo whateve 1}")
  check node.kind == GeneSet
  check node.set_elems.count == 3

  node = read("#{}")
  check node.kind == GeneSet
  check node.set_elems.count == 0

  # node = read("#:foo {:x 1}")
  # check node.kind == GeneMap
  # check node.map.count == 1
  # check node.map[new_gene_keyword("foo", "x")].get == new_gene_int(1)

  node = read("1/2")
  check node.kind == GeneRatio
  check node.rnum == (BiggestInt(1), BiggestInt(2))

  node = read("{:ratio -1/2}")
  check node.kind == GeneMap
  check node.map[new_gene_keyword("", "ratio")].get == new_gene_ratio(-1, 2)

  # node = read("#foo.bar -1")
  # check node.kind == GeneTaggedValue
  # check node.value.kind == GeneInt
  # check node.value == new_gene_int(-1)

  # node = read("#foo.bar [1 2 \"balls\"]")
  # check node.kind == GeneTaggedValue
  # check node.value.kind == GeneVector

  node = read("#(or % disabled)")
  check node.kind == GeneGene

  # let's set up conditional forms reading
  var opts: ParseOptions
  opts.conditional_exprs = asTagged
  init_gene_readers(opts)

  # # conditional compilation exprs
  # node = read("#+clj #{foo}")
  # check node.tag == ("", "+clj")
  # check node.kind == GeneTaggedValue
  # check node.value.kind == GeneSet

  # opts.conditional_exprs = cljSource
  # init_gene_readers(opts)
  # node = read("#+clj #{foo}")
  # check node.kind == GeneSet
  # node = read("#+cljs {}")
  # check node == nil

  # node = read("[1 2 #+cljs 3 4]")
  # check node.kind == GeneVector
  # check node.vec.len == 3

  var opts1: ParseOptions
  opts1.eof_is_error = true
  opts1.suppress_read = false
  opts1.conditional_exprs = cljSource

  # TODO: conditionals are not working
  # node = read("#?(:clj :x)", opts1)
  # check node.kind == GeneKeyword

  # TODO: conditionals are not working
  # node = read("#?(:cljs :x)", opts1)
  # check node == nil

  # TODO: conditionals are not working
  # try:
  #   node = read("#?(:cljs :x :clj)", opts1)
  #   check false
  # except ParseError:
  #   discard

  # TODO: conditionals are not working
  # node = read("[1 2 #?(:clj 3)]", opts1)
  # check node.kind == GeneVector
  # check node.vec.len == 3

  # TODO: conditionals are not working
  # opts1.conditional_exprs = cljsSource
  # node = read("[1 2 #?(:clj 3)]", opts1)
  # check node.kind == GeneVector
  # check node.vec.len == 2


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
