# To run these tests, simply execute `nimble test` or `nim c -r tests/test_interpreter.nim`

import tables

import gene/types
import ./helpers

test_eval "nil", GeneNil
test_eval "1", new_gene_int(1)
test_eval "true", GeneTrue
test_eval "false", GeneFalse

test_eval "1 2 3", new_gene_int(3)

test_eval "[]", new_gene_vec()
test_eval "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_eval "{}", new_gene_map(Table[string, GeneValue]())
test_eval "{:a 1}", new_gene_map({"a": new_gene_int(1)}.toTable)

test_eval "(1 + 2)", new_gene_int(3)
test_eval "(1 - 2)", new_gene_int(-1)

test_eval "(1 == 1)", GeneTrue
test_eval "(1 == 2)", GeneFalse
test_eval "(1 < 0)", GeneFalse
test_eval "(1 < 1)", GeneFalse
test_eval "(1 < 2)", GeneTrue
test_eval "(1 <= 0)", GeneFalse
test_eval "(1 <= 1)", GeneTrue
test_eval "(1 <= 2)", GeneTrue

test_eval "(true && false)", GeneFalse
test_eval "(true && true)", GeneTrue
test_eval "(true || false)", GeneTrue
test_eval "(false && false)", GeneFalse

test_eval "(var a 1) a", new_gene_int(1)
test_eval "(var a 1) (a = 2) a", new_gene_int(2)
test_eval "(var a) (a = 2) a", new_gene_int(2)

test_eval "(if true 1)", new_gene_int(1)
test_eval "(if false 1 else 2)", new_gene_int(2)
test_eval """
  (if false
    1
  elif true
    2
  else
    3
  )
""", new_gene_int(2)

test_eval "(fn f [] 1) (f)", new_gene_int(1)
test_eval "(fn f a (a + 1)) (f 1)", new_gene_int(2)
test_eval """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", new_gene_int(8)

# test_eval "(class A)", new_gene_map({"a": new_gene_int(1)}.toTable)