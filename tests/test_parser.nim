# To run these tests, simply execute `nimble test` or `nim c -r tests/test_parser.nim`

import unittest, options, tables, unicode, times, re

import gene/types

import ./helpers

# 0b... Bin
# 0o... Oct
# 0x... Hex
# 0s... Base64

test_parser "nil", GeneNil
test_parser "true", true
test_parser "false", false

test_parser "10", 10
test_parser "-1", -1
test_parser "10e10", 10e10
test_parser "+5.0E5", +5.0E5

test_parser "'t", 't'
test_parser "'t,", 't'
test_parser "'\\t", '\t'
test_parser "'\\tab", '\t'
test_parser "'中", "中".runeAt(0)

test_parser "\"test\"", "test"
test_parser ",\"test\",", "test"

test_parser "a", new_gene_symbol("a")
test_parser "A", new_gene_symbol("A")
test_parser "+a", new_gene_symbol("+a")
test_parser "#a", new_gene_symbol("#a")
# test_parser "a:b", new_gene_symbol("a:b") # good or bad?
test_parser "n/A", new_gene_complex_symbol("n", @["A"])
test_parser "n/m/A", new_gene_complex_symbol("n", @["m", "A"])
test_parser "/A", new_gene_complex_symbol("", @["A"])
test_parser "\\true", new_gene_symbol("true")
# test_parser "^a", new_gene_symbol("^a")
test_parser "symbol-👋", new_gene_symbol("symbol-👋")
test_parser "+foo+", new_gene_symbol("+foo+")

test_parser "#/b/", proc(r: GeneValue) =
  check r.kind == GeneRegex
  check "ab".find(r.regex) == 1
  check "AB".find(r.regex) == -1

# i: ignore case
# m: multi-line mode, ^ and $ matches beginning and end of each line
test_parser "#/b/i", proc(r: GeneValue) =
  check r.kind == GeneRegex
  check "ab".find(r.regex) == 1
  check "AB".find(r.regex) == 1

test_parser "2020-12-02", new_gene_date(2020, 12, 02)
test_parser "2020-12-02T10:11:12Z",
  new_gene_datetime(init_date_time(02, cast[Month](12), 2020, 10, 11, 12, utc()))
test_parser "10:11:12", new_gene_time(10, 11, 12)

test_parser "{}", OrderedTable[string, GeneValue]()
test_parser "{^a 1}", {"a": new_gene_int(1)}.toOrderedTable

test_parser "[]", new_gene_vec()
test_parser "[,]", new_gene_vec()
test_parser "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))
test_parser "[1, 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_parser "#[]", new_gene_set()
test_parser "#[1 2]", new_gene_set(new_gene_int(1), new_gene_int(2))

test_parser ",a", new_gene_symbol("a")
test_parser "a,", new_gene_symbol("a")

test_parser "1 2 3", 1

test_parser "()", proc(r: GeneValue) =
  check r.gene.type == nil
  check r.gene.props.len == 0
  check r.gene.data.len == 0

test_parser "(())", proc(r: GeneValue) =
  check r.kind == GeneGene
  check r.gene.data.len == 0
  check r.gene.type.kind == GeneGene
  check r.gene.type.gene.data.len == 0

test_parser "(1 2 3)", proc(r: GeneValue) =
  check r.gene.type == 1
  check r.gene.data == @[new_gene_int(2), new_gene_int(3)]

test_parser """
  (_ 1 "test")
""", proc(r: GeneValue) =
  check r[0] == 1
  check r[1] == "test"

test_parser "(1 ^a 2 3 4)", proc(r: GeneValue) =
  check r.gene.type == 1
  check r.gene.props == {"a": new_gene_int(2)}.toOrderedTable
  check r.gene.data == @[new_gene_int(3), new_gene_int(4)]

test_parser "(1 2 ^a 3 4)", proc(r: GeneValue) =
  check r.gene.type == 1
  check r.gene.props == {"a": new_gene_int(3)}.toOrderedTable
  check r.gene.data == @[new_gene_int(2), new_gene_int(4)]

test_parser "(1 ^^a 2 3)", proc(r: GeneValue) =
  check r.gene.type == 1
  check r.gene.props == {"a": GeneTrue}.toOrderedTable
  check r.gene.data == @[new_gene_int(2), new_gene_int(3)]

test_parser "(1 ^!a 2 3)", proc(r: GeneValue) =
  check r.gene.type == 1
  check r.gene.props == {"a": GeneFalse}.toOrderedTable
  check r.gene.data == @[new_gene_int(2), new_gene_int(3)]

test_parser "{^^x ^!y ^^z}", proc(r: GeneValue) =
  check r.kind == GeneMap
  check r.map == {"x": GeneTrue, "y": GeneFalse, "z": GeneTrue}.toOrderedTable

test_parser ":foo", proc(r: GeneValue) = # -> (quote foo)
  check r.kind == GeneGene
  check r.gene.type == new_gene_symbol("quote")
  check r.gene.data == @[new_gene_symbol("foo")]

test_parser "%foo", proc(r: GeneValue) = # -> (unquote foo)
  check r.kind == GeneGene
  check r.gene.type == new_gene_symbol("unquote")
  check r.gene.data == @[new_gene_symbol("foo")]

test_parser "%_foo", proc(r: GeneValue) = # -> (unquote foo)
  check r.kind == GeneGene
  check r.gene.type == new_gene_symbol("unquote")
  check r.gene.props["discard"] == GeneTrue
  check r.gene.data == @[new_gene_symbol("foo")]

# TODO: %_ is not allowed on gene type and property value
# (%_foo)         should throw error
# (a ^name %_foo) should throw error
# {^name %_foo}   should throw error

# test_parser "#_ [foo bar]", proc(r: GeneValue) =
#   check r == nil

test_parser "1/2", proc(r: GeneValue) =
  check r.kind == GeneRatio
  check r.ratio == (BiggestInt(1), BiggestInt(2))

test_parser "{^ratio -1/2}", proc(r: GeneValue) =
  check r.kind == GeneMap
  check r.map["ratio"] == new_gene_ratio(-1, 2)

test_parser_error "{^ratio 1/-2}"

test_read_all """
  1 # comment
  2
""", proc(r: seq[GeneValue]) =
  check r[0] == 1
  check r[1] == 2

test_read_all """
  1 ##comment
  2
""", proc(r: seq[GeneValue]) =
  check r[0] == 1
  check r[1] == 2

test_read_all "a,b", proc(r: seq[GeneValue]) =
  check r[0] == new_gene_symbol("a")
  check r[1] == new_gene_symbol("b")

test_read_all "1 2", @[new_gene_int(1), new_gene_int(2)]

test_parser """
  [
    1 # test
  ]
""", @[new_gene_int(1)]

test_parser """
  #
  # comment
  #
  1
  #
""", 1

test_parser "[a/[1 2]]", proc(r: GeneValue) =
  check r.vec[0].csymbol.first == "a"
  check r.vec[0].csymbol.rest == @[""]
  check r.vec[1].vec[0] == 1
  check r.vec[1].vec[1] == 2

test_parser """
  #< comment ># 1
""", 1

test_parser """
  #< #<< comment >># ># 1
""", 1

test_parser """
  #<
  comment
  #># 1
""", 1

test_parser """
  #<
  comment
  #>## 1
  2
""", 2

test_parser """
  #<
  #<<
  comment
  #>>#
  #># 1
""", 1

test_parse_document """
  ^name "Test document"
  ^version "0.1.0"
""", proc(r: GeneDocument) =
  check r.props["name"] == "Test document"
  check r.props["version"] == "0.1.0"
  check r.data.len == 0

test_parse_document """
  ^name "Test document"
  1 2
""", proc(r: GeneDocument) =
  check r.props["name"] == "Test document"
  check r.data == @[new_gene_int(1), new_gene_int(2)]

test_parser "\"\"\"a\"\"\"", "a"
# Trim whitespaces and new line after opening """
# E.g. """  \na""" => "a"
test_parser "\"\"\"  \na\"\"\"", "a"
# Trim whitespaces before closing """
# E.g. """a\n   """ => "a\n"
test_parser "\"\"\"a\n   \"\"\"", "a\n"
