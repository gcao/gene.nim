import lexbase, streams, strutils, unicode, hashes, tables

import ./types

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

  CommentsHandling* = enum
    discardComments, keepComments

  ParseOptions* = object
    eof_is_error*: bool
    eof_value*: GeneValue
    suppress_read*: bool
    comments_handling*: CommentsHandling

  Parser* = object of BaseLexer
    a: string
    token*: TokenKind
    err: GeneError
    filename: string
    options*: ParseOptions

  ParseError* = object of CatchableError
  ParseInfo = tuple[line, col: int]

  MacroReader = proc(p: var Parser): GeneValue
  MacroArray = array[char, MacroReader]

# const non_constituents = ['@', '`', '~']
const non_constituents = ['`', '~']

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

### === ERROR HANDLING UTILS ===

proc err_info(p: Parser): ParseInfo =
  result = (p.line_number, get_col_number(p, p.bufpos))

### === MACRO READERS ===

proc read*(p: var Parser): GeneValue

# proc valid_utf8_alpha(c: char): bool =
#   return c.isAlphaAscii() or c >= 0xc0

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
  result = GeneValue(kind: GeneGene, gene: Gene())
  result.gene.op = new_gene_symbol(quote_name)
  result.gene.data = @[quoted]

proc read_quoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "quote")

proc read_quasiquoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "quasiquote")

proc read_unquoted*(p: var Parser): GeneValue =
  return read_quoted_internal(p, "unquote")

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
  let ch = p.buf[pos]
  if ch == EndOfFile:
    raise new_exception(ParseError, "EOF while reading character")

  result = GeneValue(kind: GeneChar)
  let token = read_token(p, false)
  if token.len == 1:
    result.char = token[0]
  elif token == "\\n" or token == "\\newline":
    result.char = '\c'
  elif token == "\\s" or token == "\\space":
    result.char = ' '
  elif token == "\\t" or token == "\\tab":
    result.char = '\t'
  elif token == "\\b" or token == "\\backspace":
    result.char = '\b'
  elif token == "\\f" or token == "\\formfeed":
    result.char = '\f'
  elif token == "\\r" or token == "\\return":
    result.char = '\r'
  elif token.startsWith("\\u"):
    # TODO: impl unicode char reading
    raise new_exception(ParseError, "Not implemented: reading unicode chars")
  elif token.runeLen == 1:
    result.rune = token.runeAt(0)
  else:
    raise new_exception(ParseError, "Unknown character: " & token)

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
  var s = s
  if s.startsWith("\\"):
    s = s[1..^1]
  let split_sym = s.split('/')
  if split_sym.len > 1:
    return new_gene_complex_symbol(split_sym[0], split_sym[1..^1])
  else:
    return new_gene_symbol(s)

proc interpret_token(token: string): GeneValue =
  case token
  of "nil":
    return GeneNil
  of "true":
    return new_gene_bool(token)
  of "false":
    return new_gene_bool(token)
  else:
    result = match_symbol(token)
    if result == nil:
      raise new_exception(ParseError, "Invalid token: " & token)


proc attach_comment_lines(node: GeneValue, comment_lines: seq[string], placement: CommentPlacement): void =
  todo()
  # var co = new(Comment)
  # co.placement = placement
  # co.comment_lines = comment_lines
  # if node.comments.len == 0: node.comments = @[co]
  # else: node.comments.add(co)

type DelimitedListResult = object
  list: seq[GeneValue]
  comment_lines: seq[string]
  comment_placement: CommentPlacement

proc read_gene_op(p: var Parser): GeneValue =
  var delimiter = ')'
  # the bufpos should be already be past the opening paren etc.
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
      # Do not increase position because we need to read other components in Gene
      # inc(pos)
      # p.bufpos = pos
      # make sure any comments get attached
      if with_comments and comment_lines.len > 0:
        attach_comment_lines(result, comment_lines, After)
        comment_lines = @[]
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      p.bufpos = pos
      result = m(p)
      if result != nil:
        if ch == ';' and result.kind == GeneCommentLine:
          if with_comments:
            comment_lines.add(result.comment)
          else:
            discard
        else:
          inc(count)
          # attach comments encountered before this node
          if with_comments and comment_lines.len > 0:
            attach_comment_lines(result, comment_lines, Before)
            comment_lines = @[]
          break
    else:
      result = read(p)
      if result != nil:
        if with_comments:
          case result.kind
          of GeneCommentLine:
            comment_lines.add(result.comment)
          else:
            if comment_lines.len > 0:
              attach_comment_lines(result, comment_lines, Before)
              comment_lines = @[]
            inc(count)
            break
        else: # discardComments
          case result.kind
          of GeneCommentLine:
            discard
          else:
            inc(count)
            break

proc read_delimited_list(p: var Parser, delimiter: char, is_recursive: bool): DelimitedListResult =
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

proc add_line_col(p: var Parser, node: var GeneValue): void =
  discard
  # node.line = p.line_number
  # node.column = getColNumber(p, p.bufpos)

proc maybe_add_comments(node: GeneValue, list_result: DelimitedListResult): GeneValue =
  discard
  # if list_result.comment_lines.len > 0:
  #   var co = new(Comment)
  #   co.placement = Inside
  #   co.comment_lines = list_result.comment_lines
  #   if node.comments.len == 0: node.comments = @[co]
  #   else: node.comments.add(co)
  #   return node

type
  PropState = enum
    Key
    Value

proc read_map(p: var Parser, part_of_gene: bool): Table[string, GeneValue] =
  result = Table[string, GeneValue]()
  var ch: char
  var key: string
  var state = PropState.Key
  while true:
    skip_ws(p)
    ch = p.buf[p.bufpos]
    if ch == EndOfFile:
      raise new_exception(ParseError, "EOF while reading Gene")
    elif ch == ']' or (part_of_gene and ch == '}') or (not part_of_gene and ch == ')'):
      raise new_exception(ParseError, "Unmatched delimiter: " & p.buf[p.bufpos])
    elif ch == ';':
      discard read_comment(p)
      continue
    case state:
    of Key:
      if ch == '^':
        p.bufPos.inc
        if p.buf[p.bufPos] == '^':
          p.bufPos.inc
          key = read_token(p, false)
          result[key] = GeneTrue
        elif p.buf[p.bufPos] == '!':
          p.bufPos.inc
          key = read_token(p, false)
          result[key] = GeneFalse
        else:
          key = read_token(p, false)
          state = PropState.Value
      elif part_of_gene:
        if ch == ')':
          p.bufPos.inc
        return
      elif ch == '}':
        p.bufPos.inc
        return
      else:
        raise new_exception(ParseError, "Expect key at " & $p.bufpos & " but found " & p.buf[p.bufpos])
    of PropState.Value:
      if ch == '^':
        raise new_exception(ParseError, "Expect value for " & key)
      elif part_of_gene:
        if ch == ')':
          raise new_exception(ParseError, "Expect value for " & key)
        else:
          state = PropState.Key
          result[key] = read(p)
      else:
        if ch == '}':
          raise new_exception(ParseError, "Expect value for " & key)
        else:
          state = PropState.Key
          result[key] = read(p)

proc read_gene(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneGene, gene: Gene())
  #echo "line ", getCurrentLine(p), "lineno: ", p.line_number, " col: ", getColNumber(p, p.bufpos)
  #echo $get_current_line(p) & " LINENO(" & $p.line_number & ")"
  add_line_col(p, result)
  result.gene.op = read_gene_op(p)
  skip_ws(p)
  if p.buf[p.bufpos] == '^':
    let props = read_map(p, true)
    result.gene.props = props
  var result_list = read_delimited_list(p, ')', true)
  result.gene.data = result_list.list
  discard maybe_add_comments(result, result_list)

proc read_map(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneMap)
  let map = read_map(p, false)
  result.map = map

proc read_vector(p: var Parser): GeneValue =
  result = GeneValue(kind: GeneVector)
  let list_result = read_delimited_list(p, ']', true)
  result.vec = list_result.list
  discard maybe_add_comments(result, list_result)

proc hash*(node: GeneValue): Hash =
  var h: Hash = 0
  h = h !& hash(node.kind)
  case node.kind
  of GeneAny:
    todo()
  of GeneNilKind, GenePlaceholderKind:
    discard
  of GeneBool:
    h = h !& hash(node.bool)
  of GeneChar:
    h = h !& hash(node.char)
  of GeneInt:
    h = h !& hash(node.int)
  of GeneRatio:
    h = h !& hash(node.ratio)
  of GeneFloat:
    h = h !& hash(node.float)
  of GeneString:
    h = h !& hash(node.str)
  of GeneSymbol:
    h = h !& hash(node.symbol)
  of GeneComplexSymbol:
    h = h !& hash(node.csymbol.first & "/" & node.csymbol.rest.join("/"))
  of GeneGene:
    if node.gene.op != nil:
      h = h !& hash(node.gene.op)
    h = h !& hash(node.gene.data)
  of GeneMap:
    for key, val in node.map:
      h = h !& hash(key)
      h = h !& hash(val)
  of GeneVector:
    h = h !& hash(node.vec)
  of GeneCommentLine:
    h = h !& hash(node.comment)
  of GeneRegex:
    h = h !& hash(node.regex)
  of GeneInternal:
    todo($node.internal.kind)
  result = !$h

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
    raise  new_exception(ParseError, "No dispatch macro for: " & ch)
  else:
    p.bufpos = pos + 1
    result = m(p)

proc init_macro_array() =
  macros['"'] = read_string
  macros[':'] = read_quoted
  macros['\''] = read_character
  macros['`'] = read_quasi_quoted
  macros[';'] = read_comment
  macros['~'] = read_unquoted
  # macros['@'] = read_deref
  macros['#'] = read_dispatch
  # macros['\\'] = read_character
  macros['('] = read_gene
  macros['{'] = read_map
  macros['['] = read_vector
  macros[')'] = read_unmatched_delimiter
  macros[']'] = read_unmatched_delimiter
  macros['}'] = read_unmatched_delimiter

proc init_dispatch_macro_array() =
  dispatch_macros['!'] = read_comment
  dispatch_macros[' '] = read_comment
  # dispatch_macros[':'] = read_ns_map
  # dispatch_macros['<'] = nil  # new UnreadableReader();
  dispatch_macros['_'] = read_discard
  dispatch_macros['"'] = read_regex

proc init_gene_readers() =
  init_macro_array()
  init_dispatch_macro_array()

proc init_gene_readers*(options: ParseOptions) =
  discard

init_gene_readers()

### === TODO: name for this section ====

proc open*(p: var Parser, input: Stream, filename: string) =
  lexbase.open(p, input)
  p.filename = filename
  p.a = ""

proc close*(p: var Parser) {.inline.} =
  lexbase.close(p)

# proc get_line(p: Parser): int {.inline.} =
#   result = p.line_number

# proc get_column(p: Parser): int {.inline.} =
#   result = get_col_number(p, p.bufpos)

# proc get_filename(p: Parser): string =
#   result = p.filename

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
        result = new_gene_ratio(numerator.int, denom.int)
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
  let noComments = p.options.comments_handling != keepComments
  while result != nil and noComments and result.kind == GeneCommentLine:
    result = read_internal(p)

proc read*(s: Stream, filename: string): GeneValue =
  var p: Parser
  var opts: ParseOptions
  opts.eof_is_error = true
  opts.suppress_read = false
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
    elif p.options.comments_handling != keepComments and node.kind == GeneCommentLine:
      continue
    else:
      result.add(node)

proc read_document*(buffer: string): GeneDocument =
  return new_doc(read_all(buffer))

proc read*(buffer: string, options: ParseOptions): GeneValue =
  var
    p: Parser
    s = new_string_stream(buffer)
  p.options = options
  p.open(s, "*input*")
  defer: p.close()
  result = read(p)
