import unittest

import gene/types

import ./helpers

test_interpreter "(ns test)", proc(r: GeneValue) =
  check r.internal.ns.name == "test"

test_interpreter """
  (ns n
    (class A)
  )
  n/A
""", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_interpreter """
  (ns n)
  n
""", proc(r: GeneValue) =
  check r.internal.ns.name == "n"

test_interpreter "global", new_gene_internal(APP.ns)

test_interpreter """
  (class global/A)
  global/A
""", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_interpreter """
  (var global/a 1)
  a
""", 1
