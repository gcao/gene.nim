import ./types

proc init_native_procs*() =
  NativeProcs.add_only "str_len", proc(args: seq[GeneValue]): GeneValue = 
    return args[0].str.len