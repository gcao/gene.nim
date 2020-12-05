{.push dynlib exportc.}

import tables

import gene/types

proc test*(props: OrderedTable[string, GeneValue], data: seq[GeneValue]): GeneValue =
  var first = data[0].int
  var second = data[1].int
  return new_gene_int(first + second)

{.pop.}