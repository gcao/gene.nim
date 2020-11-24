import tables

import ./types

proc search(self: SelectorMatcher, target: GeneValue): GeneValue =
  case self.kind:
  of SmIndex:
    case target.kind:
    of GeneVector:
      return target.vec[self.index]
    else:
      todo()
  of SmName:
    case target.kind:
    of GeneMap:
      return target.map[self.name]
    else:
      todo()
  else:
    todo()

proc search(self: SelectorItem, target: GeneValue): GeneValue =
  var r: seq[GeneValue] = @[]
  for m in self.matchers:
    try:
      r.add(m.search(target))
    except SelectorNoResult:
      discard
  if self.children.len > 0:
    result = new_gene_vec()
    for child in self.children:
      for item in r:
        result.vec.add(child.search(item).vec)
  else:
    result = new_gene_vec(r)

proc search*(self: Selector, target: GeneValue): GeneValue =
  case self.mode:
  of SelFirst:
    for child in self.children:
      try:
        return child.search(target)
      except SelectorNoResult:
        discard
  of SelAll:
    todo()
