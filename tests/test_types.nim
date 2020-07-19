# To run these tests, simply execute `nimble test` or `nim c -r tests/test_types.nim`

import unittest

import gene/types

test "normalize":
  var value = new_gene_gene(
    new_gene_int(1),
    @[
      new_gene_symbol("+"),
      new_gene_int(2),
    ],
  )
  value.normalize
  check value == new_gene_gene(
    new_gene_symbol("+"),
    @[
      new_gene_int(1),
      new_gene_int(2),
    ],
  )
