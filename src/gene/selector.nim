import tables

import ./map_key
import ./types

let NO_RESULT = new_gene_gene(new_gene_symbol("SELECTOR_NO_RESULT"))

#################### Definitions #################

proc search*(self: Selector, target: GeneValue, r: SelectorResult)

##################################################

proc search_first(self: SelectorMatcher, target: GeneValue): GeneValue =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      return target.vec[self.index]
    of GeneGene:
      return target.gene.data[self.index]
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      return target.map[self.name]
    of GeneGene:
      return target.gene.props[self.name]
    of GeneInternal:
      case target.internal.kind:
      of GeneInstance:
        return target.internal.instance.value.gene.props[self.name]
      else:
        todo()
    else:
      todo()
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          return item
    else:
      todo()
  else:
    todo()

proc add_self_and_descendants(self: var seq[GeneValue], v: GeneValue) =
  self.add(v)
  case v.kind:
  of GeneVector:
    for child in v.vec:
      self.add_self_and_descendants(child)
  of GeneGene:
    for child in v.gene.data:
      self.add_self_and_descendants(child)
  else:
    discard

proc search(self: SelectorMatcher, target: GeneValue): seq[GeneValue] =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      result.add(target.vec[self.index])
    of GeneGene:
      result.add(target.gene.data[self.index])
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      result.add(target.map[self.name])
    else:
      todo()
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    of GeneGene:
      for item in target.gene.data:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    else:
      todo()
  of SmSelfAndDescendants:
    result.add_self_and_descendants(target)
  else:
    todo()

proc search(self: SelectorItem, target: GeneValue, r: SelectorResult) =
  case self.kind:
  of SiDefault:
    if self.is_last():
      case r.mode:
      of SrFirst:
        for m in self.matchers:
          var v = m.search_first(target)
          if v != NO_RESULT:
            r.done = true
            r.first = v
            break
      of SrAll:
        for m in self.matchers:
          r.all.add(m.search(target))
    else:
      var items: seq[GeneValue] = @[]
      for m in self.matchers:
        try:
          items.add(m.search(target))
        except SelectorNoResult:
          discard
      for child in self.children:
        for item in items:
          child.search(item, r)
  of SiSelector:
    self.selector.search(target, r)

proc search(self: Selector, target: GeneValue, r: SelectorResult) =
  case r.mode:
  of SrFirst:
    for child in self.children:
      child.search(target, r)
      if r.done:
        return
  else:
    for child in self.children:
      child.search(target, r)

proc search*(self: Selector, target: GeneValue): GeneValue =
  if self.is_singular():
    var r = SelectorResult(mode: SrFirst)
    self.search(target, r)
    if r.done:
      result = r.first
      # TODO: invoke callbacks
    else:
      raise new_exception(SelectorNoResult, "No result is found for the selector.")
  else:
    var r = SelectorResult(mode: SrAll)
    self.search(target, r)
    result = new_gene_vec(r.all)
    # TODO: invoke callbacks

proc update(self: SelectorItem, target: GeneValue, value: GeneValue): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      case target.kind:
      of GeneVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      else:
        todo()
    of SmByName:
      case target.kind:
      of GeneMap:
        if self.is_last:
          target.map[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.map[m.name], value)
      of GeneInternal:
        case target.internal.kind:
        of GeneInstance:
          var g = target.internal.instance.value.gene
          if self.is_last:
            g.props[m.name] = value
            result = true
          else:
            for child in self.children:
              result = result or child.update(g.props[m.name], value)
        else:
          todo()
      else:
        todo()
    else:
      todo()

proc update*(self: Selector, target: GeneValue, value: GeneValue): bool =
  for child in self.children:
    result = result or child.update(target, value)
