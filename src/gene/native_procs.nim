import strutils, tables, osproc, json, httpclient, base64

import ./types

proc init_native_procs*() =
  NativeProcs.add_only "object_is", proc(args: seq[GeneValue]): GeneValue =
    return args[0].is_a(args[1].internal.class)

  NativeProcs.add_only "object_to_json", proc(args: seq[GeneValue]): GeneValue =
    return args[0].to_json()

  NativeProcs.add_only "class_new", proc(args: seq[GeneValue]): GeneValue =
    var name = args[0].symbol_or_str
    result = new_class(name)
    result.internal.class.parent = args[1].internal.class

  NativeProcs.add_only "class_name", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0]
    if self.kind == GeneInternal and self.internal.kind == GeneClass:
      return self.internal.class.name
    else:
      not_allowed($self & " is not a class.")

  NativeProcs.add_only "class_parent", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0]
    if self.kind == GeneInternal and self.internal.kind == GeneClass:
      return self.internal.class.parent
    else:
      not_allowed($self & " is not a class.")

  NativeProcs.add_only "exception_message", proc(args: seq[GeneValue]): GeneValue =
    var ex = args[0].internal.exception
    return ex.msg

  NativeProcs.add_only "package_name", proc(args: seq[GeneValue]): GeneValue =
    return args[0].internal.pkg.name

  NativeProcs.add_only "str_size", proc(args: seq[GeneValue]): GeneValue =
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
      var maxsplit = args[2].int - 1
      var parts = self.split(separator, maxsplit)
      result = new_gene_vec()
      for part in parts:
        result.vec.add(part)
    else:
      not_allowed("split expects 1 or 2 arguments")

  NativeProcs.add_only "str_index", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    var substr = args[1].str
    result = self.find(substr)

  NativeProcs.add_only "str_rindex", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    var substr = args[1].str
    result = self.rfind(substr)

  NativeProcs.add_only "str_char_at", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    var i = args[1].int
    result = self[i]

  NativeProcs.add_only "str_trim", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    result = self.strip

  NativeProcs.add_only "str_starts_with", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    var substr = args[1].str
    result = self.startsWith(substr)

  NativeProcs.add_only "str_ends_with", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    var substr = args[1].str
    result = self.endsWith(substr)

  NativeProcs.add_only "str_to_upper_case", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    result = self.toUpper

  NativeProcs.add_only "str_to_lower_case", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].str
    result = self.toLower

  NativeProcs.add_only "array_size", proc(args: seq[GeneValue]): GeneValue =
    return args[0].vec.len

  NativeProcs.add_only "array_get", proc(args: seq[GeneValue]): GeneValue =
    return args[0].vec[args[1].int]

  NativeProcs.add_only "array_set", proc(args: seq[GeneValue]): GeneValue =
    args[0].vec[args[1].int] = args[2]

  NativeProcs.add_only "array_add", proc(args: seq[GeneValue]): GeneValue =
    args[0].vec.add(args[1])
    return args[0]

  NativeProcs.add_only "array_del", proc(args: seq[GeneValue]): GeneValue =
    var self = args[0].vec
    var index = args[1].int
    result = self[index]
    self.delete(index)

  NativeProcs.add_only "map_size", proc(args: seq[GeneValue]): GeneValue =
    return args[0].map.len

  NativeProcs.add_only "gene_type", proc(args: seq[GeneValue]): GeneValue =
    return args[0].gene.type

  NativeProcs.add_only "gene_props", proc(args: seq[GeneValue]): GeneValue =
    return args[0].gene.props

  NativeProcs.add_only "gene_data", proc(args: seq[GeneValue]): GeneValue =
    return args[0].gene.data

  NativeProcs.add_only "file_open", proc(args: seq[GeneValue]): GeneValue =
    var file = open(args[0].str)
    result = file

  NativeProcs.add_only "file_close", proc(args: seq[GeneValue]): GeneValue =
    args[0].internal.file.close

  NativeProcs.add_only "file_read", proc(args: seq[GeneValue]): GeneValue =
    var file = args[0]
    case file.kind:
    of GeneString:
      result = read_file(file.str)
    else:
      var internal = args[0].internal
      if internal.kind == GeneFile:
        return internal.file.read_all

  NativeProcs.add_only "file_write", proc(args: seq[GeneValue]): GeneValue =
    var file = args[0]
    var content = args[1]
    write_file(file.str, content.str)

  NativeProcs.add_only "os_exec", proc(args: seq[GeneValue]): GeneValue =
    var cmd = args[0].str
    # var cmd_args = args[1].vec.map(proc(v: GeneValue):string = v.to_s)
    var (output, _) = execCmdEx(cmd)
    result = output

  NativeProcs.add_only "json_parse", proc(args: seq[GeneValue]): GeneValue =
    return args[0].str.parse_json

  NativeProcs.add_only "http_get", proc(args: seq[GeneValue]): GeneValue =
    var url = args[0].str
    var headers = newHttpHeaders()
    for k, v in args[2].map:
      headers.add(k, v.str)
    var client = newHttpClient()
    client.headers = headers
    return client.get_content(url)

  NativeProcs.add_only "base64", proc(args: seq[GeneValue]): GeneValue =
    return encode(args[0].str)
