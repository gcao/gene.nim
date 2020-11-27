import strutils, tables

import ./types

const SIMPLE_BINARY_OPS* = [
  "+", "-", "*", "/",
  "=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

type
  Normalizer* = proc(self: GeneValue): bool

var Normalizers: seq[Normalizer]

# Important: order of normalizers matters. normalize() should be tested as a whole

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type`.kind == GeneSymbol:
    if `type`.symbol.startsWith(".@"):
      var new_type = new_gene_symbol("@")
      var new_gene = new_gene_gene(new_type)
      new_gene.gene.normalized = true
      if `type`.symbol.len > 2:
        var name = `type`.symbol.substr(2).to_selector_matcher()
        new_gene.gene.data.insert(name, 0)
      else:
        for item in self.gene.data:
          new_gene.gene.data.add(item)
      self.gene.type = new_gene
      self.gene.data = @[new_gene_symbol("self")]
      return true
    elif `type`.symbol[0] == '.' and `type`.symbol != "...":  # (.method x y z)
      self.gene.props["self"] = new_gene_symbol("self")
      self.gene.props["method"] = new_gene_string_move(`type`.symbol.substr(1))
      self.gene.type = new_gene_symbol("$invoke_method")
  elif `type`.kind == GeneComplexSymbol and `type`.csymbol.first.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    var name = `type`.csymbol.first.substr(2).to_selector_matcher()
    new_gene.gene.data.insert(name, 0)
    for part in `type`.csymbol.rest:
      new_gene.gene.data.add(part.to_selector_matcher())
    self.gene.type = new_gene
    self.gene.data = @[new_gene_symbol("self")]
    return true

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type` == If:
    var i = 1  # start index after condition
    var cond = self.gene.data[0]
    if cond == Not:
      cond = new_gene_gene(Not, self.gene.data[1])
      i += 1
    var then_blk: seq[GeneValue] = @[]
    var else_blk: seq[GeneValue] = @[]
    var state = "cond"
    while i < self.gene.data.len:
      var item = self.gene.data[i]
      case state:
      of "cond":
        if item == Then:
          discard
        elif item == Else:
          state = "else"
        else:
          then_blk.add(item)
      of "else":
        else_blk.add(item)
      i += 1
    self.gene.props["cond"] = cond
    self.gene.props["then"] = then_blk
    self.gene.props["else"] = else_blk
    self.gene.data.reset

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type`.kind == GeneSymbol:
    if `type`.symbol == "import" or `type`.symbol == "import_native":
      var names: seq[GeneValue] = @[]
      var module: GeneValue
      var expect_module = false
      for val in self.gene.data:
        if expect_module:
          module = val
        elif val.kind == GeneSymbol and val.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.gene.props["names"] = new_gene_vec(names)
      self.gene.props["module"] = module
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.type.kind == GeneSymbol:
    if self.gene.type.symbol == "fnx":
      self.gene.type = new_gene_symbol("fn")
      self.gene.data.insert(new_gene_symbol("_"), 0)
      return true
    elif self.gene.type.symbol == "fnxx":
      self.gene.type = new_gene_symbol("fn")
      self.gene.data.insert(new_gene_symbol("_"), 0)
      self.gene.data.insert(new_gene_symbol("_"), 0)
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol:
    if first.symbol == "+=":
      self.gene.type = new_gene_symbol("=")
      var second = self.gene.data[1]
      self.gene.data[0] = type
      self.gene.data[1] = new_gene_gene(new_gene_symbol("+"), `type`, second)
      return true
    elif first.symbol == "=" and `type`.kind == GeneSymbol and `type`.symbol.startsWith("@"):
      # (@prop = val)
      self.gene.type = new_gene_symbol("$set")
      self.gene.data[0] = `type`
      self.gene.data.insert(new_gene_symbol("self"), 0)
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var first = self.gene.data[0]
  if first.kind != GeneSymbol or first.symbol notin SIMPLE_BINARY_OPS:
    return false

  self.gene.data.delete 0
  self.gene.data.insert self.gene.type, 0
  self.gene.type = first
  return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    if first.symbol.len == 2:
      for i in 1..<self.gene.data.len:
        new_gene.gene.data.add(self.gene.data[i])
    else:
      new_gene.gene.data.add(first.symbol.substr(2).to_selector_matcher())
    self.gene.data = @[`type`]
    self.gene.type = new_gene
    return true
  elif first.kind == GeneComplexSymbol and first.csymbol.first.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    var name = first.csymbol.first.substr(2).to_selector_matcher()
    new_gene.gene.data.add(name)
    for part in first.csymbol.rest:
      new_gene.gene.data.add(part.to_selector_matcher())
    self.gene.data = @[`type`]
    self.gene.type = new_gene
    return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol[0] == '.' and first.symbol != "...":
    self.gene.props["self"] = `type`
    self.gene.props["method"] = new_gene_string_move(first.symbol.substr(1))
    self.gene.data.delete 0
    self.gene.type = new_gene_symbol("$invoke_method")
    return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol == "->":
    self.gene.props["args"] = self.gene.type
    self.gene.type = self.gene.data[0]
    self.gene.data.delete 0
    return true

# # Normalize symbols like "a..." etc
# # @Return: a normalized value to replace the original value
# proc normalize_symbol(self: GeneValue): GeneValue =
#   todo()

# Normalize self.vec, self.gene.data, self.map, self.gene.props etc but don't go further
proc normalize_children*(self:  GeneValue) =
  todo()

proc normalize*(self:  GeneValue) =
  if self.kind != GeneGene or self.gene.normalized:
    return
  if self.gene.type == Quote:
    return
  for n in Normalizers:
    if n(self):
      break
  self.gene.normalized = true
