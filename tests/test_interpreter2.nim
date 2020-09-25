import gene/types
import ./helpers

test_interpreter "nil", GeneNil
test_interpreter "1", 1
test_interpreter "1 2", 2
test_interpreter "(1 + 2)", 3
