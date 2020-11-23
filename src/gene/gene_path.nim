import tables

import ./types

proc search(self: GenePathMatcher, target: GeneValue): GeneValue =
  case self.kind:
  of GpmName:
    case target.kind:
    of GeneMap:
      return target.map[self.name]
    else:
      todo()
  else:
    todo()

proc search(self: GenePathItem, target: GeneValue): GeneValue =
  var r: seq[GeneValue] = @[]
  for m in self.matchers:
    try:
      r.add(m.search(target))
    except GenePathNoResult:
      discard
  result = new_gene_vec(r)

proc search*(self: GenePath, target: GeneValue): GeneValue =
  case self.mode:
  of GpFirst:
    for item in self.paths:
      try:
        return item.search(target)
      except GenePathNoResult:
        discard
  of GpAll:
    todo()
