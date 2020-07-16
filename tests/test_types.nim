# To run these tests, simply execute `nimble test`.

import unittest

import gene/types

test "Types":
  var value = GeneValue(
    kind: GeneGene,
    gene_op: new_gene_int(1),
    gene_data: @[
      new_gene_symbol("+"),
      new_gene_int(2),
    ],
  )
  value.normalize
  check value.gene_op == new_gene_symbol("+")
  check value.gene_data[0] == new_gene_int(1)
  check value.gene_data[1] == new_gene_int(2)
