import unittest

import gene/types
import gene/interpreter

# import ./helpers

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
