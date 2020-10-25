import strutils

import ./types

proc init_native_procs*() =
  NativeProcs.add_only "str_len", proc(args: seq[GeneValue]): GeneValue = 
    return args[0].str.len
  NativeProcs.add_only "str_substr", proc(args: seq[GeneValue]): GeneValue = 
    case args.len:
    of 2:
      var self = args[0].str
      var start = args[1].int
      if start >= 0:
        return self[start..^1]
      else:
        return self[^(-start)..^1]
    of 3:
      var self = args[0].str
      var start = args[1].int
      var end_index = args[2].int
      if start >= 0:
        if end_index >= 0:
          return self[start..end_index]
        else:
          return self[start..^(-end_index)]
      else:
        if end_index >= 0:
          return self[^(-start)..end_index]
        else:
          return self[^(-start)..^(-end_index)]
    else:
      not_allowed("substr expects 1 or 2 arguments")

  NativeProcs.add_only "str_split", proc(args: seq[GeneValue]): GeneValue = 
    var self = args[0].str
    var separator = args[1].str
    case args.len:
    of 2:
      var parts = self.split(separator)
      result = new_gene_vec()
      for part in parts:
        result.vec.add(part)
    of 3:
      var limit = args[2].int
      var parts = self.split(separator, limit)
      result = new_gene_vec()
      for part in parts:
        result.vec.add(part)
    else:
      not_allowed("split expects 1 or 2 arguments")
