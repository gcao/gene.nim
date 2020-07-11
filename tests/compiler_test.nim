# To run these tests, simply execute `nimble test`.

import gene/types
import ./test_helper

test_compiler "1",
  new_gene_int(1)
test_compiler "(1 + 2)",
  new_gene_int(3)
test_compiler "(if true 1)",
  new_gene_int(1)
test_compiler "(if false 1 else 2)",
  new_gene_int(2)
test_compiler "(if false 1 elif true 2 else 3)",
  new_gene_int(2)
test_compiler "(if false 1 elif false 2 else 3)",
  new_gene_int(3)

test_compiler "(fn f [] 1) (f)",
  new_gene_int(1)
