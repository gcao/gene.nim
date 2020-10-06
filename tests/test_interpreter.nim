import unittest, tables

import gene/types

import ./helpers

test_interpreter "nil", GeneNil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false
test_interpreter "\"string\"", "string"

test_interpreter "1 2 3", 3

test_interpreter "[]", new_gene_vec()
test_interpreter "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_interpreter "{}", Table[string, GeneValue]()
test_interpreter "{:a 1}", {"a": new_gene_int(1)}.toTable

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

test_interpreter "(fn f a a)", proc(r: GeneValue) =
  check r.internal.fn.name == "f"

test_interpreter "(fn f [] 1) (f)", 1
test_interpreter "(fn f a (a + 1)) (f 1)", 2

test_interpreter """
  (fn f []
    (return 1)
    2
  )
  (f)
""", 1

test_interpreter """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", 8

test_interpreter "self", GeneNil

test_interpreter """
  ($call_native "str_len" "test")
""", 4
