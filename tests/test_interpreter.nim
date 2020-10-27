import unittest, tables

import gene/types

import ./helpers

test_interpreter "nil", GeneNil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false
test_interpreter "\"string\"", "string"
test_interpreter ":a", new_gene_symbol("a")

test_interpreter "1 2 3", 3

test_interpreter "[]", new_gene_vec()
test_interpreter "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_interpreter "{}", Table[string, GeneValue]()
test_interpreter "{^a 1}", {"a": new_gene_int(1)}.toTable

test_interpreter "(:test 1 2)", proc(r: GeneValue) =
  check r.gene.op == new_gene_symbol("test")
  check r.gene.data[0] == 1
  check r.gene.data[1] == 2

test_interpreter "(range 0 100)", proc(r: GeneValue) =
  check r.range_start == 0
  check r.range_end == 100

test_interpreter "(1 + 2)", 3
test_interpreter "(1 - 2)", -1

test_interpreter "(1 == 1)", true
test_interpreter "(1 == 2)", false
test_interpreter "(1 < 0)", false
test_interpreter "(1 < 1)", false
test_interpreter "(1 < 2)", true
test_interpreter "(1 <= 0)", false
test_interpreter "(1 <= 1)", true
test_interpreter "(1 <= 2)", true

test_interpreter "(true && false)", false
test_interpreter "(true && true)", true
test_interpreter "(true || false)", true
test_interpreter "(false && false)", false

test_interpreter "(var a 1) a", 1
test_interpreter "(var a 1) (a = 2) a", 2
test_interpreter "(var a) (a = 2) a", 2

test_interpreter """
  (var a 1)
  (var b 2)
  [a b]
""", proc(r: GeneValue) =
  check r.vec[0] == 1
  check r.vec[1] == 2

test_interpreter """
  (var a 1)
  (var b 2)
  {^a a ^b b}
""", proc(r: GeneValue) =
  check r.map["a"] == 1
  check r.map["b"] == 2

test_interpreter """
  (var a 1)
  (var b 2)
  (:test ^a a b)
""", proc(r: GeneValue) =
  check r.gene.props["a"] == 1
  check r.gene.data[0] == 2

test_interpreter "(if true 1)", 1
test_interpreter "(if false 1 else 2)", 2
# test_interpreter """
#   (if false
#     1
#   elif true
#     2
#   else
#     3
#   )
# """, 2

test_interpreter "(do 1 2)", 2

test_interpreter """
  (var i 0)
  (loop
    (i = (i + 1))
    (break)
  )
  i
""", 1

test_interpreter """
  (var i 0)
  (loop
    (i = (i + 1))
    (break i)
  )
""", 1

test_interpreter """
  (var i 0)
  (while (i < 3)
    (i = (i + 1))
  )
  i
""", 3

test_interpreter """
  (var sum 0)
  (for i in (range 0 4)
    (sum += i)
  )
  sum
""", 6 # 0 + 1 + 2 + 3

test_interpreter """
  (var sum 0)
  (for i in [1 2 3]
    (sum += i)
  )
  sum
""", 6

# test_interpreter """
#   (var sum)
#   (for [k v] in {^a 1 ^b 2}
#     (sum += v)
#   )
#   sum
# """, 3

test_interpreter "self", GeneNil

test_interpreter """
  (call_native "str_size" "test")
""", 4

test_interpreter """
  (var a 1)
  (var b 2)
  (eval :a :b)
""", 2

# TODO: (caller_eval ...) = (eval ^context caller_context ...)

test_interpreter """
  (var a (:test 1))
  ($set a 0 2)
  ($get a 0)
""", 2

test_interpreter """
  (var i 1) # first i
  (fn f _
    i       # reference to first i
  )
  (var i 2) # second i
  (f)
""", 1
