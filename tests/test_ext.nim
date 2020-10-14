{.push dynlib exportc.}

import gene/types

proc test*(args: seq[GeneValue]): GeneValue =
  var first = args[0].int
  var second = args[1].int
  return new_gene_int(first + second)

{.pop.}
