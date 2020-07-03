import lexbase, streams, strutils, parseutils, unicode, nre, tables, hashes, options

import types

type
  TokenKind* = enum
    tkError,
    tkEof,
    tkString,
    tkInt,
    tkFloat

  GeneError* = enum
    errNone,
    errInvalidToken,
    errEofExpected,
    errQuoteExpected

  ConditionalExpressionsHandling* = enum
    asError, asTagged, cljSource, cljsSource

  CommentsHandling* = enum
    discardComments, keepComments

  ParseOptions* = object
    eof_is_error*: bool
    eof_value*: GeneValue
    suppress_read*: bool
    conditional_exprs*: ConditionalExpressionsHandling
    comments_handling*: CommentsHandling

  Parser* = object of BaseLexer
    a: string
    token*: TokenKind
    err: GeneError
    filename: string
    options*: ParseOptions

  ParseError* = object of Exception
  ParseInfo = tuple[line, col: int]

  MacroReader = proc(p: var Parser): GeneValue
  MacroArray = array[char, MacroReader]

const non_constituents = ['@', '`', '~']

converter to_int(c: char): int = result = ord(c)

var
  macros: MacroArray
  dispatch_macros: MacroArray

proc non_constituent(c: char): bool =
  result = non_constituents.contains(c)

proc is_macro(c: char): bool =
  result = c.to_int < macros.len and macros[c] != nil

proc is_terminating_macro(c: char): bool =
  result = c != '#' and c != '\'' and is_macro(c)

proc get_macro(ch: char): MacroReader =
  result = macros[ch]

## ============== HMAP TYPE AND FWD DECLS ===========

proc new_hmap*(capacity: int = 16): HMap

proc `[]=`*(m: HMap, key: GeneValue, val: GeneValue)

proc val_at*(m: HMap, key: GeneValue, default: GeneValue = nil): GeneValue

proc `[]`*(m: HMap, key: GeneValue): Option[GeneValue]

proc len*(m: HMap): int = m.count

iterator items*(m: HMap): HMapEntry =
  for b in m.buckets:
    if len(b) != 0:
      for entry in b:
        yield entry

proc merge_maps*(m1, m2 :HMap): void

proc add_meta*(node: GeneValue, meta: HMap): GeneValue

## ============== NEW OBJ FACTORIES =================

let
  gene_true*  = GeneValue(kind: GeneBool, bool_val: true)
  gene_false* = GeneValue(kind: GeneBool, bool_val: false)

proc new_gene_string_move(s: string): GeneValue =
  result = GeneValue(kind: GeneString)
  shallowCopy(result.str, s)

proc new_gene_int*(s: string): GeneValue =
  return GeneValue(kind: GeneInt, num: parseBiggestInt(s))

proc new_gene_int*(val: int): GeneValue =
  return GeneValue(kind: GeneInt, num: val)

proc new_gene_ratio*(nom, denom: BiggestInt): GeneValue =
  return GeneValue(kind: GeneRatio, rnum: (nom, denom))

proc new_gene_float*(s: string): GeneValue =
  return GeneValue(kind: GeneFloat, fnum: parseFloat(s))

proc new_gene_float*(val: float): GeneValue =
  return GeneValue(kind: GeneFloat, fnum: val)

proc new_gene_bool*(val: bool): GeneValue =
  case val
  of true: return gene_true
  of false: return gene_false
  # of true: return GeneValue(kind: GeneBool, boolVal: true)
  # of false: return GeneValue(kind: GeneBool, boolVal: false)

proc new_gene_bool*(s: string): GeneValue =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_symbol*(ns, name: string): GeneValue =
  return GeneValue(kind: GeneSymbol, symbol: (ns, name))

proc new_gene_keyword*(ns, name: string): GeneValue =
  return GeneValue(kind: GeneKeyword, keyword: (ns, name))

proc new_gene_nil*(): GeneValue =
  new(result)

### === VALS ===

let
  GeneTrue: GeneValue  = gene_true
  GeneFalse: GeneValue = gene_false
  KeyTag*: GeneValue   = new_gene_keyword("", "tag")
  CljTag: GeneValue   = new_gene_keyword("", "clj")
  CljsTag: GeneValue  = new_gene_keyword("", "cljs")
  DefaultTag: GeneValue = new_gene_keyword("", "default")

  LineKw: GeneValue   = new_gene_keyword("gene.nim", "line")
  ColumnKw: GeneValue   = new_gene_keyword("gene.nim", "column")
  SplicedQKw*: GeneValue = new_gene_keyword("gene.nim", "spliced?")

### === ERROR HANDLING UTILS ===

proc err_info(p: Parser): ParseInfo =
  result = (p.line_number, get_col_number(p, p.bufpos))

### === MACRO READERS ===

proc read*(p: var Parser): GeneValue

proc valid_utf8_alpha(c: char): bool =
  return c.isAlphaAscii() or c >= 0xc0

proc handle_hex_char(c: char, x: var int): bool =
  result = true
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else: result = false

proc parse_escaped_utf16(buf: cstring, pos: var int): int =
  result = 0
  for _ in 0..3:
    if handle_hex_char(buf[pos], result):
      inc(pos)
    else:
      return -1

proc parse_string(p: var Parser): TokenKind =
  result = tkString
  var pos = p.bufpos
  var buf = p.buf
  while true:
    case buf[pos]
    of '\0':
      p.err = errQuoteExpected
    of '"':
      inc(pos)
      break;
    of '\\':
      case buf[pos+1]
      of '\\', '"', '\'', '/':
        add(p.a, buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(p.a, '\b')
        inc(pos, 2)
      of 'f':
        add(p.a, '\b')
        inc(pos, 2)
      of 'n':
        add(p.a, '\L')
        inc(pos, 2)
      of 'r':
        add(p.a, '\C')
        inc(pos, 2)
      of 't':
        add(p.a, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parse_escaped_utf16(buf, pos)
        if r < 0:
          p.err = errInvalidToken
          break
        # deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if buf[pos] & buf[pos + 1] != "\\u":
            p.err = errInvalidToken
            break
          inc(pos, 2)
          var s = parse_escaped_utf16(buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            p.err = errInvalidToken
            break
        add(p.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(p.a, buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(p, pos)
      buf = p.buf
      add(p.a, '\c')
    of '\L':
      pos = lexbase.handleLF(p, pos)
      buf = p.buf
      add(p.a, '\L')
    else:
      add(p.a, buf[pos])
      inc(pos)
  p.bufpos = pos

proc read_string(p: var Parser): GeneValue =
  discard parse_string(p)
  if p.err != errNone:
    raise newException(ParseError, "read_string failure: " & $p.err)
  result = new_gene_string_move(p.a)
  p.a = ""

proc read_quoted_internal(p: var Parser, quote_name: string): GeneValue =
  let quoted = read(p)
  result = GeneValue(kind: GeneGene)
  result.list = @[new_gene_symbol("", quote_name), quoted]

proc read_quoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "quote")

proc read_quasiquoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "quasiquote")

proc read_unquoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "unquote")

proc read_deref*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "deref")

# TODO: read comment as continuous blocks, not just lines
proc read_comment(p: var Parser): GeneValue =
  var pos = p.bufpos
  var buf = p.buf
  result = GeneValue(kind: GeneCommentLine)
  if p.options.comments_handling == keepComments:
    while true:
      case buf[pos]
      of '\L':
        pos = lexbase.handleLF(p, pos)
        break
      of '\c':
        pos = lexbase.handleCR(p, pos)
        break
      of EndOfFile:
        raise new_exception(ParseError, "EOF while reading comment")
      else:
        add(p.a, buf[pos])
        inc(pos)
    p.bufpos = pos
    result.comment = p.a
    p.a = ""
  else:
    while true:
      case buf[pos]
      of '\L':
        pos = lexbase.handleLF(p, pos)
        break
      of '\c':
        pos = lexbase.handleCR(p, pos)
        break
      of EndOfFile:
        raise new_exception(ParseError, "EOF while reading comment")
      else:
        inc(pos)
    p.bufpos = pos

proc read_token(p: var Parser, lead_constituent: bool): string =
  var pos = p.bufpos
  var ch = p.buf[pos]
  if lead_constituent and non_constituent(ch):
    raise new_exception(ParseError, "Invalid leading character " & ch)
  else:
    result = ""
    result.add(ch)
  while true:
    inc(pos)
    ch = p.buf[pos]
    if ch == EndOfFile or isSpaceAscii(ch) or is_terminating_macro(ch):
      break
    elif non_constituent(ch):
      raise new_exception(ParseError, "Invalid constituent character: " & ch)
    result.add(ch)
  p.bufpos = pos

proc read_character(p: var Parser): GeneValue =
  var pos = p.bufpos
  #var buf = p.buf
  let ch = p.buf[pos]
  if ch == EndOfFile:
    raise new_exception(ParseError, "EOF while reading character")

  result = GeneValue(kind: GeneChar)
  let token = read_token(p, false)
  if token.len == 1:
    result.character = token[0]
  elif token == "newline":
    result.character = '\c'
  elif token == "space":
    result.character = ' '
  elif token == "tab":
    result.character = '\t'
  elif token == "backspace":
    result.character = '\b'
  elif token == "formfeed":
    result.character = '\f'
  elif token == "return":
    result.character = '\r'
  elif token.startsWith("u"):
    # TODO: impl unicode char reading
    raise new_exception(ParseError, "Not implemented: reading unicode chars")
  elif token.startsWith("o"):
    # TODO: impl unicode char reading
    raise new_exception(ParseError, "Not implemented: reading unicode chars")

proc skip_ws(p: var Parser) =
  # commas are whitespace in gene collections
  var pos = p.bufpos
  var buf = p.buf
  while true:
    case buf[pos]
    of ' ', '\t', ',':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(p, pos)
      buf = p.buf
    of '\L':
      pos = lexbase.handleLF(p, pos)
      buf = p.buf
    else:
      break
  p.bufpos = pos

proc match_symbol(s: string): GeneValue =
  let
    ns_pat   = re"[:]?([\D].*)"
    name_pat = re"(\D.*)"
    split_sym = s.split('/')
  var
    ns: string
    name: string
  case split_sym.len
  of 1:
    ns   = ""
    name = split_sym[0]
  of 2:
    ns   = split_sym[0]
    name = split_sym[1]
  else:
    return nil

  if ns != "":
    let ns_m = ns.match(ns_pat)
    if ns_m.is_some():
      ns = ns_m.get().captures[0]
  if name != "":
    let name_m = name.match(name_pat)
    if name_m.is_some():
      name = name_m.get().captures[0]
  if s[0] == ':':
    result = GeneValue(kind: GeneKeyword)
    # locally namespaced kw (e.g. ::foo)
    if split_sym.len == 1:
      if 2 < s.high() and s[1] == ':':
        result.keyword = (ns, name.substr(2, name.len))
        result.is_namespaced = true
      else:
        result.keyword = (ns, name.substr(1,name.len))
        result.is_namespaced = false
    else:
      result.keyword = (ns, name)
      result.is_namespaced = false
  else:
    result = GeneValue(kind: GeneSymbol)
    result.symbol = (ns, name)

proc interpret_token(token: string): GeneValue =
  result = nil
  case token
  of "nil":
    result = new_gene_nil()
  of "true":
    result = new_gene_bool(token)
  of "false":
    result = new_gene_bool(token)
  else:
    result = nil

  if result == nil:
    result = match_symbol(token)
  if result == nil:
    raise new_exception(ParseError, "Invalid token: " & token)


proc attach_comment_lines(node: GeneValue, comment_lines: seq[string], placement: CommentPlacement): void =
  var co = new(Comment)
  co.placement = placement
  co.comment_lines = comment_lines
  if node.comments.len == 0: node.comments = @[co]
  else: node.comments.add(co)
  
type DelimitedListResult = object
  list: seq[GeneValue]
  comment_lines: seq[string]
  comment_placement: CommentPlacement

proc read_delimited_list(
  p: var Parser, delimiter: char, is_recursive: bool): DelimitedListResult =
  # the bufpos should be already be past the opening paren etc.
  var list: seq[GeneValue] = @[]
  var comment_lines: seq[string] = @[]
  var count = 0
  let with_comments = keepComments == p.options.comments_handling
  while true:
    skip_ws(p)
    var pos = p.bufpos
    let ch = p.buf[pos]
    if ch == EndOfFile:
      let msg = "EOF while reading list $# $# $#"
      raise new_exception(ParseError, format(msg, delimiter, p.filename, p.line_number))

    if ch == delimiter:
      inc(pos)
      p.bufpos = pos
      # make sure any comments get attached
      if with_comments and list.len > 0 and comment_lines.len > 0:
        var node = list[list.high]
        attach_comment_lines(node, comment_lines, After)
        comment_lines = @[]
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      p.bufpos = pos
      let node = m(p)
      if node != nil:
        if ch == ';' and node.kind == GeneCommentLine:
          if with_comments:
            comment_lines.add(node.comment)
          else:
            discard
        else:
          inc(count)
          list.add(node)
          # attach comments encountered before this node
          if with_comments and comment_lines.len > 0:
            attach_comment_lines(node, comment_lines, Before)
            comment_lines = @[]
    else:
      let node = read(p)
      if node != nil:
        if with_comments:
          case node.kind
          of GeneCommentLine:
            comment_lines.add(node.comment)
          else:
            if comment_lines.len > 0:
              attach_comment_lines(node, comment_lines, Before)
              comment_lines = @[]
            inc(count)
            list.add(node)
        else: # discardComments
          case node.kind
          of GeneCommentLine:
            discard
          else:
            inc(count)
            list.add(node)
              
  if comment_lines.len == 0:
    result.comment_lines = @[]
  else:
    result.comment_lines = comment_lines
    result.comment_placement = Inside
  result.list = list

proc add_line_col_meta(p: var Parser, node: var GeneValue): void =
  let m = new_hmap()
  node.line = p.line_number
  node.column = getColNumber(p, p.bufpos)
  discard add_meta(node, m)

proc maybe_add_comments(node: GeneValue, list_result: DelimitedListResult): GeneValue =
  if list_result.comment_lines.len > 0:
    var co = new(Comment)
    co.placement = Inside
    co.comment_lines = list_result.comment_lines
    if node.comments.len == 0: node.comments = @[co]
    else: node.comments.add(co)
    return node

proc read_list(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneGene)
  #echo "line ", getCurrentLine(p), "lineno: ", p.line_number, " col: ", getColNumber(p, p.bufpos)
  #echo $get_current_line(p) & " LINENO(" & $p.line_number & ")"
  add_line_col_meta(p, result)
  var result_list = read_delimited_list(p, ')', true)
  result.list = result_list.list
  discard maybe_add_comments(result, result_list)

const
  MAP_EVEN = "Map literal must contain even number of forms "

proc read_map(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneMap)
  var list_result = read_delimited_list(p, '}', true)
  var list = list_result.list
  var index = 0
  if (list.len and 1) == 1:
    for x in list:
      if index mod 2 == 0 and x.kind == GeneKeyword:
        echo "MAP ELEM " & $x.kind & " " & $x.keyword
      else:
        echo "MAP ELEM " & $x.kind
    inc(index)
    let position = (p.line_number, get_col_number(p, p.bufpos))
    #echo "line ", getCurrentLine(p), " col: ", getColNumber(p, p.bufpos)
    raise new_exception(ParseError, MAP_EVEN & $position & " " & $list.len & " " & p.filename)
  else:
    result.map = new_hmap()
    var i = 0
    while i <= list.high - 1:
      result.map[list[i]] = list[i+1]
      i = i + 2
  add_line_col_meta(p, result)
  discard maybe_add_comments(result, list_result)

const
  NS_MAP_INVALID = "Namespaced map must specify a valid namespace: kind $#, namespace $#, $#:$#"
  NS_MAP_EVEN = "Namespaced map literal must contain an even number of forms"

proc read_ns_map(p: var Parser): GeneValue =
  let n = read(p)
  if n.kind != GeneSymbol or n.symbol.ns != "":
    let ns_str = if n.symbol.ns == "": "nil" else: n.symbol.ns
    raise new_exception(ParseError, format(NS_MAP_INVALID, n.kind, ns_str, p.filename, p.line_number))

  skip_ws(p)

  if p.buf[p.bufpos] != '{':
    raise new_exception(ParseError, "Namespaced map must specify a map")
  inc(p.bufpos)
  let list_result = read_delimited_list(p, '}', true)
  let list = list_result.list
  if (list.len and 1) == 1:
    raise new_exception(ParseError, NS_MAP_EVEN)
  var
    map = new_hmap()
    i = 0
  while i < list.high:
    var key = list[i]
    inc(i)
    var value = list[i]
    inc(i)
    case key.kind
    of GeneKeyword:
      if key.keyword.ns == "":
        map[new_gene_keyword(n.symbol.name, key.keyword.name)] = value
      elif key.keyword.ns == "_":
        map[new_gene_keyword("", key.keyword.name)] = value
      else:
        map[key] = value
    of GeneSymbol:
      if key.symbol.ns == "":
        map[new_gene_symbol(n.symbol.name, key.symbol.name)] = value
      elif key.keyword.ns == "_":
        map[new_gene_keyword("", key.symbol.name)] = value
      else:
        map[key] = value
    else:
      map[key] = value

    result = GeneValue(kind: GeneMap, map: map)
    discard maybe_add_comments(result, list_result)

proc read_vector(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneVector)
  let list_result = read_delimited_list(p, ']', true)
  result.vec = list_result.list
  discard maybe_add_comments(result, list_result)

proc read_set(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneSet)
  let list_result = read_delimited_list(p, '}', true)
  var elements = list_result.list
  discard maybe_add_comments(result, list_result)
  var i = 0
  # TODO: hmap_capacity(len(elements))
  result.set_elems = new_hmap()
  while i <= elements.high:
    result.set_elems[elements[i]] = new_gene_bool(true)
    inc(i)
    
proc read_anonymous_fn*(p: var Parser): GeneValue =
  # TODO: extract arglist from fn body
  result = GeneValue(kind: GeneGene)
  var arglist = GeneValue(kind: GeneVector, vec:  @[])
  result.list = @[new_gene_symbol("", "fn")]
  # remember this one came from a macro
  let meta = new_hmap()
  meta[new_gene_keyword("", "from-reader-macro")] = new_gene_bool(true)
  result.list_meta = meta

  var list_result = read_delimited_list(p, ')', true)
  for item in list_result.list:
    result.list.add(item)
  discard maybe_add_comments(result, list_result)
  return result

proc safely_add_meta(node: GeneValue, meta: HMap): GeneValue

const
  READER_COND_MSG = "reader conditional should be a list: "
  READER_COND_FEAT_KW = "feature should be a keyword: "
  READER_COND_AS_TAGGED_ERR = "'asTagged' option not available for reader conditionals"

proc read_reader_conditional(p: var Parser): GeneValue =
  # '#? (:clj ...)'
  let pos = p.bufpos
  var is_spliced: bool
  if p.buf[pos] == '@':
    is_spliced = true
    inc(p.bufpos)
  else:
    is_spliced = false
    
  let exp = read(p)
  if exp.kind != GeneGene:
    raise new_exception(ParseError, READER_COND_MSG & $exp.kind)
  var
    i = 0
    m = new_hmap()
  while i <= exp.list.high:
    let feature = exp.list[i]
    if feature.kind != GeneKeyword:
      raise new_exception(ParseError, READER_COND_FEAT_KW & $feature.kind & " line " & $p.line_number)
    inc(i)
    var val: GeneValue
    if i <= exp.list.high:
      val = exp.list[i]
      # TODO: does not verify if we're trying to splice at toplevel
      if is_spliced and (val.kind != GeneVector):
        raise new_exception(ParseError, "Trying to splice a conditional expression with: " & $val.kind & ", element " & $i)
      inc(i)
    else:
      let msg = format("No value for platform tag: $#, line $#", feature.keyword, feature.line)
      raise new_exception(ParseError, msg)
    m[feature] = val

  let cond_exprs = p.options.conditional_exprs
  case cond_exprs
  of asError:
    raise new_exception(ParseError, "Reader conditional occured")
  of asTagged:
    raise new_exception(ParseError, READER_COND_AS_TAGGED_ERR)
  of cljSource:
    let val = m[CljTag]
    if is_some(val):
      result = val.get
    else: result = nil
  of cljsSource:
    let val = m[CljsTag]
    if is_some(val):
      result = val.get
    else: result = nil

  # try the :default case
  if result == nil:
    let default_val = m[DefaultTag]
    if is_some(default_val):
      result = default_val.get

  #TODO: better handle splicing - new node type or sth else?
  if result != nil and is_spliced:
    var hmap = new_hmap()
    hmap[SplicedQKw] = GeneTrue
    discard add_meta(result, hmap)
  
  return result




const META_CANNOT_APPLY_MSG =
  "Metadata can be applied only to symbols, lists, vectors and map. Got :"

proc add_meta*(node: GeneValue, meta: HMap): GeneValue =
  case node.kind
  of GeneSymbol:
    node.symbol_meta = meta
  of GeneGene:
    node.list_meta = meta
  of GeneMap:
    node.map_meta = meta
  of GeneVector:
    node.vec_meta = meta
  else:
    raise new_exception(ParseError, META_CANNOT_APPLY_MSG & $node.kind)
  result = node

proc get_meta*(node: GeneValue): HMap =
  case node.kind
  of GeneSymbol:
    return node.symbol_meta
  of GeneGene:
    return node.list_meta
  of GeneMap:
    return node.map_meta
  of GeneVector:
    return node.vec_meta
  else:
    raise new_exception(ParseError, "Given type does not support metadata")

proc safely_add_meta(node: GeneValue, meta: HMap): GeneValue =
  var node_meta = get_meta(node)
  if node_meta == nil:
    return add_meta(node, meta)
  else:
    merge_maps(node_meta, meta)
    return node

const META_INVALID_MSG =
  "Metadata must be GeneSymbol, GeneKeyword, GeneString or GeneMap"

proc read_metadata(p: var  Parser): GeneValue =
  var m: HMap
  let old_opts = p.options
  p.options.eof_is_error = true
  var meta = read(p)
  case meta.kind
  of GeneSymbol:
    m = new_hmap()
    m[KeyTag] = meta
  of GeneKeyword:
    m = new_hmap()
    m[meta] = GeneTrue
  of GeneString:
    m = new_hmap()
    m[KeyTag] = meta
  of GeneMap:
    m = meta.map
  else:
    p.options = old_opts
    raise new_exception(ParseError, META_INVALID_MSG)
  # read the actual data
  try:
    var node = read(p)
    result = safely_add_meta(node, m) # need to make sure we don't overwrite
  finally:
    p.options = old_opts

proc read_tagged(p: var Parser): GeneValue =
  var node = read(p)
  if node.kind != GeneSymbol:
    raise new_exception(ParseError, "tag should be a symbol: " & $node.kind)
  result = GeneValue(kind: GeneTaggedValue, tag: node.symbol, value: read(p))

proc read_cond_as_tagged(p: var Parser): GeneValue =
  # reads forms like #+clj foo as GeneTaggedValue
  var tagged = read_tagged(p)
  tagged.tag = ("", "+" & tagged.tag.name)
  return tagged

proc read_cond_matching(p: var Parser, tag: string): GeneValue =
  var tagged = read_cond_as_tagged(p)
  if tagged.kind == GeneTaggedValue:
    if tagged.tag.name == tag:
      return tagged.value
    else:
      return nil
  raise new_exception(ParseError, "Expected a tagged value, got: " & $tagged.kind)

proc read_cond_clj(p:var Parser): GeneValue =
  return read_cond_matching(p, "+clj")

proc read_cond_cljs(p:var Parser): GeneValue =
  return read_cond_matching(p, "+cljs")

proc hash*(node: GeneValue): Hash =
  var h: Hash = 0
  h = h !& hash(node.kind)
  case node.kind
  of GeneNil:
    h = h !& hash(0)
  of GeneBool:
    h = h !& hash(node.bool_val)
  of GeneChar:
    h = h !& hash(node.character)
  of GeneInt:
    h = h !& hash(node.num)
  of GeneRatio:
    h = h !& hash(node.rnum)
  of GeneFloat:
    h = h !& hash(node.fnum)
  of GeneString:
    h = h !& hash(node.str)
  of GeneSymbol:
    h = h !& hash(node.symbol)
  of GeneKeyword:
    h = h !& hash(node.keyword)
    h = h !& hash(node.is_namespaced)
  of GeneGene:
    h = h !& hash(node.list)
  of GeneMap:
    for entry in node.map:
      h = h !& hash(entry.key)
      h = h !& hash(entry.value)
  of GeneVector:
    h = h !& hash(node.vec)
  of GeneSet:
    for entry in node.set_elems:
      h = h !& hash(entry.key)
      h = h !& hash(entry.value)
  of GeneTaggedValue:
    h = h !& hash(node.tag)
    h = h !& hash(node.value)
  of GeneCommentLine:
    h = h !& hash(node.comment)
  of GeneRegex:
    h = h !& hash(node.regex)
  result = !$h

proc `==`*(this, that: GeneValue): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil or this.kind != that.kind:
    return false
  else:
    case this.kind
    of GeneNil:
      return that.kind == GeneNil
    of GeneBool:
      return this.boolVal == that.boolVal
    of GeneChar:
      return this.character == that.character
    of GeneInt:
      return this.num == that.num
    of GeneRatio:
      return this.rnum == that.rnum
    of GeneFloat:
      return this.fnum == that.fnum
    of GeneString:
      return this.str == that.str
    of GeneSymbol:
      return this.symbol == that.symbol
    of GeneKeyword:
      return this.keyword == that.keyword and this.is_namespaced == that.is_namespaced
    of GeneGene:
      return this.list == that.list
    of GeneMap:
      return this.map == that.map
    of GeneVector:
      return this.vec == that.vec
    of GeneSet:
      return this.set_elems == that.set_elems
    of GeneTaggedValue:
      return this.tag == that.tag and this.value == that.value
    of GeneCommentLine:
      return this.comment == that.comment
    of GeneRegex:
      return this.regex == that.regex

proc read_regex(p: var Parser): GeneValue =
  let s = read_string(p)
  result = GeneValue(kind: GeneRegex, regex: s.str)

proc read_unmatched_delimiter(p: var Parser): GeneValue =
  raise new_exception(ParseError, "Unmatched delimiter: " & p.buf[p.bufpos])

proc read_discard(p: var Parser): GeneValue =
  discard read(p)
  result = nil

proc read_dispatch(p: var Parser): GeneValue =
  var pos = p.bufpos
  let ch = p.buf[pos]
  if ch == EndOfFile:
    raise new_exception(ParseError, "EOF while reading dispatch macro")
  let m = dispatch_macros[ch]
  if m == nil:
    if valid_utf8_alpha(ch):
      result = read_tagged(p)
    else:
      raise  new_exception(ParseError, "No dispatch macro for: " & ch)
  else:
    p.bufpos = pos + 1
    result = m(p)

proc init_macro_array() =
  macros['"'] = read_string
  macros['\''] = read_quoted
  macros['`'] = read_quasi_quoted
  macros[';'] = read_comment
  macros['~'] = read_unquoted
  macros['@'] = read_deref
  macros['#'] = read_dispatch
  macros['^'] = read_metadata
  macros['\\'] = read_character
  macros['('] = read_list
  macros['{'] = read_map
  macros['['] = read_vector
  macros[')'] = read_unmatched_delimiter
  macros[']'] = read_unmatched_delimiter
  macros['}'] = read_unmatched_delimiter

proc init_dispatch_macro_array() =
  dispatch_macros['^'] = read_metadata
  dispatch_macros[':'] = read_ns_map
  dispatch_macros['{'] = read_set
  # dispatch_macros['<'] = nil  # new UnreadableReader();
  dispatch_macros['_'] = read_discard
  dispatch_macros['('] = read_anonymous_fn
  dispatch_macros['?'] = read_reader_conditional
  dispatch_macros['"'] = read_regex

proc init_gene_readers() =
  init_macro_array()
  init_dispatch_macro_array()

proc init_gene_readers*(options: ParseOptions) =
  case options.conditional_exprs
  of asError:
    discard # the default will throw on #+clj / #+cljs
  of asTagged:
    dispatch_macros['+'] = read_cond_as_tagged
  of cljSource:
    dispatch_macros['+'] = read_cond_clj
  of cljsSource:
    dispatch_macros['+'] = read_cond_cljs

init_gene_readers()

### === HMap: a simple hash map ====

proc new_hmap(capacity: int = 16): HMap =
  assert capacity >= 0
  new(result)
  result.buckets = new_seq[seq[HMapEntry]](capacity)
  result.count = 0

proc `[]=`*(m: HMap, key: GeneValue, val: GeneValue) =
  let h = hash(key)
  if m.count + 1 > int(0.75 * float(m.buckets.high)):
    var
      new_cap = if m.count == 0: 8 else: 2 * m.buckets.high
      tmp_map = new_hmap(new_cap)
    for b in m.buckets:
      if b.len > 0:
        for entry in b:
          tmp_map[entry.key] = entry.value
    tmp_map[key] = val
    m[] = tmp_map[]
  else:
    var bucket_index = h and m.buckets.high
    var entry = new(HMapEntry)
    entry.key   = key
    entry.value = val
    if m.buckets[bucket_index].len == 0:
      m.buckets[bucket_index] = @[entry]
      inc(m.count)
    else:
      var overwritten = false
      for item in m.buckets[bucket_index]:
        if item.key == entry.key:
          item.value = val
          overwritten = true
      if not overwritten:
        m.buckets[bucket_index].add(entry)
        inc(m.count)

proc val_at*(m: HMap, key: GeneValue, default: GeneValue = nil): GeneValue =
  let
    h = hash(key)
    bucket_index = h and m.buckets.high
    bucket = m.buckets[bucket_index]
  result = default
  if bucket.len > 0:
    for entry in bucket:
      if entry.key == key:
        result = entry.value
        break


      
proc `[]`*(m: HMap, key: GeneValue): Option[GeneValue] =
  let
    default = GeneValue(kind: GeneBool, bool_val: true)
    found = val_at(m, key, default)
    pf = cast[pointer](found)
    pd = cast[pointer](default)
  if pd == pf:
    return none(GeneValue)
  else:
    return some(found)

proc merge_maps*(m1, m2 :HMap): void = 
  for entry in m2:
    m1[entry.key] = entry.value

### === TODO: name for this section ====

proc open*(p: var Parser, input: Stream, filename: string) =
  lexbase.open(p, input)
  p.filename = filename
  p.a = ""

proc close*(p: var Parser) {.inline.} =
  lexbase.close(p)

proc get_line(p: Parser): int {.inline.} =
  result = p.line_number

proc get_column(p: Parser): int {.inline.} =
  result = get_col_number(p, p.bufpos)

proc get_filename(p: Parser): string =
  result = p.filename

proc parse_number(p: var Parser): TokenKind =
  result = TokenKind.tkEof
  var
    pos = p.bufpos
    buf = p.buf
  if (buf[pos] == '-') or (buf[pos] == '+'):
    add(p.a, buf[pos])
    inc(pos)
  if buf[pos] == '.':
    add(p.a, "0.")
    inc(pos)
    result = tkFloat
  else:
    result = tkInt
    while buf[pos] in Digits:
      add(p.a, buf[pos])
      inc(pos)
    if buf[pos] == '.':
      add(p.a, '.')
      inc(pos)
      result = tkFloat
  # digits after the dot
  while buf[pos] in Digits:
    add(p.a, buf[pos])
    inc(pos)
  if buf[pos] in {'E', 'e'}:
    add(p.a, buf[pos])
    inc(pos)
    result = tkFloat
    if buf[pos] in {'+', '-'}:
      add(p.a, buf[pos])
      inc(pos)
    while buf[pos] in Digits:
      add(p.a, buf[pos])
      inc(pos)
  p.bufpos = pos

proc read_num(p: var Parser): GeneValue =
  var num_result = parse_number(p)
  let opts = p.options
  case num_result
  of tkEof:
    if opts.eof_is_error:
      raise new_exception(ParseError, "EOF while reading")
    else:
      result = nil
  of tkInt:
    if p.buf[p.bufpos] == '/':
      if not isDigit(p.buf[p.bufpos+1]):
        let e = err_info(p)
        raise new_exception(ParseError, "error reading a ratio: " & $e)
      var numerator = new_gene_int(p.a)
      inc(p.bufpos)
      p.a = ""
      var denom_tok = parse_number(p)
      if denom_tok == tkInt:
        var denom = new_gene_int(p.a)
        result = new_gene_ratio(numerator.num, denom.num)
      else:
        raise new_exception(ParseError, "error reading a ratio: " & p.a)
    else:
      result = new_gene_int(p.a)
  of tkFloat:
    result = new_gene_float(p.a)
  of tkError:
    raise new_exception(ParseError, "error reading a number: " & p.a)
  else:
    raise new_exception(ParseError, "error reading a number (?): " & p.a)

proc read_internal(p: var Parser): GeneValue =
  setLen(p.a, 0)
  skip_ws(p)
  let ch = p.buf[p.bufpos]
  let opts = p.options
  var token: string
  case ch
  of EndOfFile:
    if opts.eof_is_error:
      let position = (p.line_number, get_col_number(p, p.bufpos))
      raise new_exception(ParseError, "EOF while reading " & $position)
    else:
      p.token = tkEof
      return opts.eof_value
  of '0'..'9':
    return read_num(p)
  elif is_macro(ch):
    let m = macros[ch] # save line:col metadata here?
    inc(p.bufpos)
    return m(p)
  elif ch in {'+', '-'}:
    if isDigit(p.buf[p.bufpos + 1]):
      return read_num(p)
    else:
      token = read_token(p, false)
      result = interpret_token(token)
      return result

  token = read_token(p, true)
  if opts.suppress_read:
    result = nil
  else:
    result = interpret_token(token)

proc read*(p: var Parser): GeneValue =
  result = read_internal(p)
  let noComments = p.options.comments_handling == discardComments
  while result != nil and noComments and result.kind == GeneCommentLine:
    result = read_internal(p)

proc read*(s: Stream, filename: string): GeneValue =
  var p: Parser
  var opts: ParseOptions
  opts.eof_is_error = true
  opts.suppress_read = false
  opts.conditional_exprs = asError
  opts.comments_handling = discardComments
  p.options = opts
  p.open(s, filename)
  defer: p.close()
  result = read(p)

proc read*(buffer: string): GeneValue =
  result = read(new_string_stream(buffer), "*input*")

proc read_all*(buffer: string): seq[GeneValue] =
  var
    p: Parser
    s = new_string_stream(buffer)
  p.open(s, "*input*")
  defer: p.close()
  while true:
    var node = p.read_internal
    if node == nil:
      return result
    else:
      result.add(node)

proc read*(buffer: string, options: ParseOptions): GeneValue =
  var
    p: Parser
    s = new_string_stream(buffer)
  p.options = options
  p.open(s, "*input*")
  defer: p.close()
  result = read(p)

proc `$`*(node: GeneValue): string =
  case node.kind
  of GeneKeyword:
    if node.is_namespaced:
      result = "::" & node.keyword.name
    elif node.keyword.ns == "":
      result = ":" & node.keyword.name
    else:
      result = ":" & node.keyword.ns & "/" & node.keyword.name
  of GeneSymbol:
    if node.symbol.ns == "":
      result = node.symbol.name
    else:
      result = node.symbol.ns & "/" & node.symbol.name
  else:
    assert(false)

# DONE: handling cond forms that are returned as nil (e.g. ommited)
# TODO: special comments handlers experimenting with literate progrmming
# TODO: util method for reading strings but accepting ParseOpts
# TODO: asTagged untested or not working? maybe drop?