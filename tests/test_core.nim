import unittest

import gene/types

import ./helpers

test_core "gene", proc(r: GeneValue) =
  check r.internal.ns.name == "gene"

test_core "genex", proc(r: GeneValue) =
  check r.internal.ns.name == "genex"

# test_core """
#   (with 1
#     self
#   )
# """, 2
