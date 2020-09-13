{.push dynlib exportc.}

import gene/types

proc test*(args: seq[GeneValue]): GeneValue =
  var first = args[0].d.num
  var second = args[1].d.num
  return new_gene_int(first + second)

{.pop.}
