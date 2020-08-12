# To run these tests, simply execute `nimble test` or `nim c -r tests/test_interpreter.nim`

import unittest, tables

import gene/types
import gene/vm
import gene/interpreter
import ./helpers

test_eval "nil", GeneNil
test_eval "1", 1
test_eval "true", true
test_eval "false", false

test_eval "1 2 3", 3

test_eval "[]", new_gene_vec()
test_eval "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_eval "{}", Table[string, GeneValue]()
test_eval "{:a 1}", {"a": new_gene_int(1)}.toTable

test_eval "(1 + 2)", 3
test_eval "(1 - 2)", -1

test_eval "(1 == 1)", true
test_eval "(1 == 2)", false
test_eval "(1 < 0)", false
test_eval "(1 < 1)", false
test_eval "(1 < 2)", true
test_eval "(1 <= 0)", false
test_eval "(1 <= 1)", true
test_eval "(1 <= 2)", true

test_eval "(true && false)", false
test_eval "(true && true)", true
test_eval "(true || false)", true
test_eval "(false && false)", false

test_eval "(var a 1) a", 1
test_eval "(var a 1) (a = 2) a", 2
test_eval "(var a) (a = 2) a", 2

test_eval "(if true 1)", 1
test_eval "(if false 1 else 2)", 2
test_eval """
  (if false
    1
  elif true
    2
  else
    3
  )
""", 2

test_eval "(do 1 2)", 2

test_eval """
  (var i 0)
  (loop
    (i = (i + 1))
    (break)
  )
  i
""", 1

test_eval """
  (var i 0)
  (loop
    (i = (i + 1))
    (break i)
  )
""", 1

test_eval """
  (var sum 0)
  (for (var i 0) (i < 5) (i += 1)
    (sum = (sum + i))
  )
  sum
""", 10

# test_eval """
#   (var i 0)
#   (while (i < 3)
#     (i = (i + 1))
#   )
#   i
# """, 3

test_eval "(fn f a a)", proc(r: GeneValue) =
  check r.internal.fn.name == "f"

test_eval "(fn f [] 1) (f)", 1
test_eval "(fn f a (a + 1)) (f 1)", 2
test_eval """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", 8

test_eval """
  (fn f []
    (return 1)
    2
  )
  (f)
""", 1

test_eval "(class A)", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_eval """
  (class A)
  (new A)
""", proc(r: GeneValue) =
  check r.instance.class.name == "A"

# @name            : get "name" property of current self
# (.@name)         : get "name" property of current self
# (.@ "name")      : get "name" property of current self
# (self .@name)    : get "name" property of current self
# (self .@ "name") : get "name" property of current self
# (@ name)         : get <name> property of current self
# (.@ name)        : get <name> property of current self
# (@name = "A")    : set "name" property of current self to "A"
# (.@name = "A")   : set "name" property of current self to "A"
# (@name= "A")     : set "name" property of current self to "A"
# (.@name= "A")    : set "name" property of current self to "A"
# (@= name "A")    : set <name> property of current self to "A"
# (a .@name)       : get "name" property of a
# (a .@name= "A")  : set "name" property of a to "A"
# (a .@= name "A") : set <name> property of a to "A"

test_eval """
  (class A
    (method new []
      (@description = "Class A")
    )
  )
  (new A)
""", proc(r: GeneValue) =
  check r.instance.value.gene_props["description"] == "Class A"

test_eval """
  (class A
    (method new []
      (@description = "Class A")
    )
  )
  ((new A) .@description)
""", proc(r: GeneValue) =
  check r.str == "Class A"

test_eval """
  (class A
    (method new description
      (@description = description)
    )
  )
  (new A "test")
""", proc(r: GeneValue) =
  check r.instance.value.gene_props["description"] == "test"

test_eval """
  (import from "src/core.gene")
  ("test" .len)
""", 4

# ($ARGV) returns command line as array of string
# ($ARGV 0) returns the program name
# ($ARGV 1) returns first argument
test_eval "($ARGV)", proc(r: GeneValue) =
  check r.vec.len == 1

test_eval "(ns test)", proc(r: GeneValue) =
  check r.internal.ns.name == "test"

test_eval """
  (ns n
    (class A)
  )
  n/A
""", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_eval """
  (ns n)
  n
""", proc(r: GeneValue) =
  check r.internal.ns.name == "n"

test_eval """
  (ns n)
  /n
""", proc(r: GeneValue) =
  check r.internal.ns.name == "n"

# * import/export
#
# file1.nim
# (ns n
#   (fn f a a)
# )
# file2.nim
# (import n from "./file1")
# n/f     # is resolved to function f in file1.nim
#
test "Interpreter / eval: import":
  var vm = new_vm()
  vm.eval_module "file1", """
    (ns n
      (fn f a a)
    )
  """
  var result = vm.eval """
    (import n from "file1")
    n/f
  """
  check result.internal.fn.name == "f"

test_eval """
  (import from "src/core.gene")
  global/String
""", proc(r: GeneValue) =
  check r.internal.class.name == "String"

test_eval """
  ($call_native "str_len" "test")
""", 4
