import unittest

import gene/types
import gene/parser
import gene/interpreter

import ./helpers

# How module / import works:
# import a, b from "module"
# import from "module" a, b
# import a, b # will import from root's parent ns (which
#    could be the package ns or global ns or a intermediate ns)
# import from "module" a/[b c], d: my_d

test "Interpreter / eval: import":
  var vm = new_vm()
  discard vm.import_module("file1", """
    (ns n
      (fn f a a)
    )
  """)
  var result = vm.eval """
    (import n from "file1")
    n/f
  """
  check result.internal.fn.name == "f"

# test "Interpreter / eval: import":
#   var vm = new_vm()
#   discard vm.import_module("file1", """
#     (ns n
#       (fn f a a)
#     )
#   """)
#   var result = vm.eval """
#     (import n/f from "file1")
#     f
#   """
#   check result.internal.fn.name == "f"

test_import_matcher "(import a b from \"module\")", proc(r: ImportMatcherRoot) =
  check r.from == "module"
  check r.children.len == 2
  check r.children[0].name == "a"
  check r.children[1].name == "b"

test_import_matcher "(import from \"module\" a b)", proc(r: ImportMatcherRoot) =
  check r.from == "module"
  check r.children.len == 2
  check r.children[0].name == "a"
  check r.children[1].name == "b"

test_import_matcher "(import a b/[c d])", proc(r: ImportMatcherRoot) =
  check r.children.len == 2
  check r.children[0].name == "a"
  check r.children[1].name == "b"
  check r.children[1].children.len == 2
  check r.children[1].children[0].name == "c"
  check r.children[1].children[1].name == "d"
