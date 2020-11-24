import tables

import ./types

#################### Definitions #################

proc search*(self: Selector, target: GeneValue): GeneValue

##################################################

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
  case self.kind:
  of SiDefault:
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
  of SiSelector:
    result = self.selector.search(target)

proc search(self: Selector, target: GeneValue, r: SelectorResult) =
  case r.mode:
  of SrFirst:
    for child in self.children:
      try:
        r.first = child.search(target)
        return
      except SelectorNoResult:
        discard
  else:
    todo()

proc search*(self: Selector, target: GeneValue): GeneValue =
  if self.is_singular():
    var r = SelectorResult(mode: SrFirst)
    self.search(target, r)
    result = r.first
  else:
    var r = SelectorResult(mode: SrAll)
    self.search(target, r)
    result = new_gene_vec(r.all)
