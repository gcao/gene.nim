# To run these tests, simply execute `nimble test`.

import unittest

import gene/types

test "Types":
  var value = GeneValue(
    kind: GeneGene,
    op: new_gene_int(1),
    list: @[
      new_gene_symbol("+"),
      new_gene_int(2),
    ],
  )
  value.normalize
  check value.op == new_gene_symbol("+")
  check value.list[0] == new_gene_int(1) 
  check value.list[1] == new_gene_int(2) 
