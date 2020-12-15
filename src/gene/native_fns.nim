import strutils, tables, osproc, json, httpclient, base64, os, times
import asyncdispatch, asyncfile

import ./map_key
import ./types

proc add_to_native*(name: string, fn: GeneValue) =
  var native = VM.gene_ns.internal.ns[NATIVE_KEY]
  if native.has_key(name.to_key):
    not_allowed()
  native.internal.ns[name.to_key] = fn

proc init_native*() =
  add_to_native "class_new",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var name = data[0].symbol_or_str
      result = new_class(name)
      result.internal.class.parent = data[1].internal.class

  add_to_native "file_open",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = open(data[0].str)
      result = file

  add_to_native "file_close",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      data[0].internal.file.close()

  add_to_native "file_read",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      case file.kind:
      of GeneString:
        result = read_file(file.str)
      else:
        var internal = data[0].internal
        if internal.kind == GeneFile:
          result = internal.file.read_all()

  add_to_native "file_read_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      case file.kind:
      of GeneString:
        var f = open_async(file.str)
        var future = f.read_all()
        var future2 = new_future[GeneValue]()
        future.add_callback proc() {.gcsafe.} =
          future2.complete(future.read())
        return future_to_gene(future2)
      else:
        todo()

  add_to_native "file_write",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      var content = data[1]
      write_file(file.str, content.str)

  add_to_native "os_exec",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var cmd = data[0].str
      # var cmd_data = data[1].vec.map(proc(v: GeneValue):string = v.to_s)
      var (output, _) = execCmdEx(cmd)
      result = output

  add_to_native "json_parse",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = data[0].str.parse_json

  add_to_native "http_get",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var url = data[0].str
      var headers = newHttpHeaders()
      for k, v in data[2].map:
        headers.add(k.to_s, v.str)
      var client = newHttpClient()
      client.headers = headers
      result = client.get_content(url)

  add_to_native "http_get_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var url = data[0].str
      var headers = newHttpHeaders()
      for k, v in data[2].map:
        headers.add(k.to_s, v.str)
      var client = newAsyncHttpClient()
      client.headers = headers
      var f = client.get_content(url)
      var future = new_future[GeneValue]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(f.read())
      result = future_to_gene(future)

  add_to_native "base64",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = encode(data[0].str)

  add_to_native "sleep",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      sleep(data[0].int)

  add_to_native "sleep_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var f = sleep_async(data[0].int)
      var future = new_future[GeneValue]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(GeneNil)
      result = future_to_gene(future)

  add_to_native "date_today",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var date = now()
      result = new_gene_date(date.year, cast[int](date.month), date.monthday)

  add_to_native "time_now",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var date = now()
      result = new_gene_datetime(date)

  add_to_native "object_is",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.is_a(data[0].internal.class)

  add_to_native "object_to_s",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.to_s()

  add_to_native "object_to_json",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.to_json()

  add_to_native "ns_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneNamespace:
        result = self.internal.ns.name
      else:
        not_allowed($self & " is not a Namespace.")

  add_to_native "class_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneClass:
        result = self.internal.class.name
      else:
        not_allowed($self & " is not a class.")

  add_to_native "class_parent",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneClass:
        result = self.internal.class.parent
      else:
        not_allowed($self & " is not a class.")

  add_to_native "exception_message",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var ex = self.internal.exception
      result = ex.msg

  add_to_native "future_finished",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.future.finished

  add_to_native "package_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.pkg.name

  add_to_native "package_version",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.pkg.version

  add_to_native "str_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.len

  add_to_native "str_append",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      for i in 1..<data.len:
        self.str.add(data[i].to_s)
      result = self

  add_to_native "str_substr",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      case data.len:
      of 1:
        var start = data[0].int
        if start >= 0:
          return self.str[start..^1]
        else:
          return self.str[^(-start)..^1]
      of 2:
        var start = data[0].int
        var end_index = data[1].int
        if start >= 0:
          if end_index >= 0:
            return self.str[start..end_index]
          else:
            return self.str[start..^(-end_index)]
        else:
          if end_index >= 0:
            return self.str[^(-start)..end_index]
          else:
            return self.str[^(-start)..^(-end_index)]
      else:
        not_allowed("substr expects 1 or 2 arguments")

  add_to_native "str_split",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var separator = data[0].str
      case data.len:
      of 1:
        var parts = self.str.split(separator)
        result = new_gene_vec()
        for part in parts:
          result.vec.add(part)
      of 2:
        var maxsplit = data[1].int - 1
        var parts = self.str.split(separator, maxsplit)
        result = new_gene_vec()
        for part in parts:
          result.vec.add(part)
      else:
        not_allowed("split expects 1 or 2 arguments")

  add_to_native "str_index",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.find(substr)

  add_to_native "str_rindex",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.rfind(substr)

  add_to_native "str_char_at",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var i = data[0].int
      result = self.str[i]

  add_to_native "str_to_i",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.parse_int

  add_to_native "str_trim",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.strip

  add_to_native "str_starts_with",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.startsWith(substr)

  add_to_native "str_ends_with",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.endsWith(substr)

  add_to_native "str_to_upper_case",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.toUpper

  add_to_native "str_to_lower_case",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.toLower

  add_to_native "date_year",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.date.year

  add_to_native "datetime_sub",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var duration = self.date.toTime() - data[0].date.toTime()
      result = duration.inMicroseconds / 1000_000

  add_to_native "datetime_elapsed",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var duration = now().toTime() - self.date.toTime()
      result = duration.inMicroseconds / 1000_000

  add_to_native "time_hour",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.time.hour

  add_to_native "array_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.vec.len

  add_to_native "array_get",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.vec[data[0].int]

  add_to_native "array_set",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      self.vec[data[0].int] = data[1]
      result = data[1]

  add_to_native "array_add",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      self.vec.add(data[0])
      result = self

  add_to_native "array_del",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var index = data[0].int
      result = self.vec[index]
      self.vec.delete(index)

  add_to_native "map_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.map.len

  add_to_native "gene_type",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.type

  add_to_native "gene_props",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.props

  add_to_native "gene_data",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.data

  # add_to_native "props_iterator",
  #   to_gene proc(args: varargs[GeneValue]): iterator(): tuple[k, v: GeneValue] =
  #     var self = args[0]
  #     result = iterator(): tuple[k, v: GeneValue] =
  #       case self.kind:
  #       of GeneGene:
  #         for k, v in self.gene.props:
  #           yield (k.to_s.str_to_gene, v)
  #       of GeneMap:
  #         for k, v in self.map:
  #           yield (k.to_s.str_to_gene, v)
  #       else:
  #         not_allowed()
