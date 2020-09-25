import gene/types
import ./helpers

test_interpreter "nil", GeneNil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false

test_interpreter "1 2", 2

test_interpreter "[]", new_gene_vec()
test_interpreter "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_interpreter "{:a 1}", {"a": new_gene_int(1)}.toTable

test_interpreter "(1 + 2)", 3
