import unittest

import gene/types

import ./helpers

test_extension "extension", "test", proc(r: NativeProc) =
  var args = @[new_gene_int(1), new_gene_int(2)]
  check r(args) == 3

test_interpreter """
  (import_native test from "extension")
  (test 1 2)
""", 3
