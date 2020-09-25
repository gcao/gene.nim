import tables

import gene/types
import ./helpers

test_interpreter "nil", GeneNil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false

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

# test_interpreter "(if true 1)", 1
# test_interpreter "(if false 1 else 2)", 2
# test_interpreter """
#   (if false
#     1
#   elif true
#     2
#   else
#     3
#   )
# """, 2

# test_interpreter "(do 1 2)", 2
