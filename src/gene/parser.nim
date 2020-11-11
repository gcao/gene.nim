# Credit:
# The parser and basic data types are built on top of EDN Parser[1] that is
# created by Roland Sadowski.
# 1. https://github.com/rosado/edn.nim

import lexbase, streams, strutils, unicode, tables, sets

import ./types

type
  ParseOptions* = object
    eof_is_error*: bool
    eof_value*: GeneValue
    suppress_read*: bool

  Parser* = object of BaseLexer
    options*: ParseOptions
    filename: string
    str: string
    document*: GeneDocument
    token*: TokenKind
    error: ParseErrorKind
    # stored_references: Table[string, GeneValue]
    document_props_done: bool  # flag to tell whether we have read document properties

  ParseError* = object of CatchableError
  ParseInfo = tuple[line, col: int]

  TokenKind* = enum
    TkError
    TkEof
    TkString
    TkInt
    TkFloat

  ParseErrorKind* = enum
    ErrNone
    ErrInvalidToken
    ErrEofExpected
    ErrQuoteExpected
    ErrRegexEndExpected

  MacroReader = proc(p: var Parser): GeneValue
  MacroArray = array[char, MacroReader]

  PropState = enum
    PropKey
    PropValue

  DelimitedListResult = object
    list: seq[GeneValue]
    map: OrderedTable[string, GeneValue]

const non_constituents = ['`', '~']

var macros: MacroArray
var dispatch_macros: MacroArray

#################### Interfaces ##################

proc read*(self: var Parser): GeneValue
proc read_internal(self: var Parser): GeneValue
proc skip_comment(self: var Parser)
proc skip_block_comment(self: var Parser)

#################### Implementations #############

converter to_int(c: char): int = result = ord(c)

proc new_parser*(options: ParseOptions): Parser =
  return Parser(
    document: GeneDocument(),
    options: options,
  )

proc new_parser*(): Parser =
  return Parser(
    document: GeneDocument(),
    options: ParseOptions(
      eof_is_error: false,
      suppress_read: false,
    ),
  )

proc non_constituent(c: char): bool =
  result = non_constituents.contains(c)

proc is_macro(c: char): bool =
  result = c.to_int < macros.len and macros[c] != nil

proc is_terminating_macro(c: char): bool =
  result = c != '#' and c != '\'' and is_macro(c)

proc get_macro(ch: char): MacroReader =
  result = macros[ch]

### === ERROR HANDLING UTILS ===

proc err_info(self: Parser): ParseInfo =
  result = (self.line_number, self.get_col_number(self.bufpos))

### === MACRO READERS ===

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

proc parse_string(self: var Parser): TokenKind =
  result = TkString
  var pos = self.bufpos
  var buf = self.buf
  while true:
    case buf[pos]
    of '\0':
      self.error = ErrQuoteExpected
    of '"':
      inc(pos)
      break
    of '\\':
      case buf[pos+1]
      of '\\', '"', '\'', '/':
        add(self.str, buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(self.str, '\b')
        inc(pos, 2)
      of 'f':
        add(self.str, '\b')
        inc(pos, 2)
      of 'n':
        add(self.str, '\L')
        inc(pos, 2)
      of 'r':
        add(self.str, '\C')
        inc(pos, 2)
      of 't':
        add(self.str, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parse_escaped_utf16(buf, pos)
        if r < 0:
          self.error = ErrInvalidToken
          break
        # deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if buf[pos] & buf[pos + 1] != "\\u":
            self.error = ErrInvalidToken
            break
          inc(pos, 2)
          var s = parse_escaped_utf16(buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            self.error = ErrInvalidToken
            break
        add(self.str, toUTF8(Rune(r)))
      else:
        # don't bother with the Error
        add(self.str, buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(self, pos)
      buf = self.buf
      add(self.str, '\c')
    of '\L':
      pos = lexbase.handleLF(self, pos)
      buf = self.buf
      add(self.str, '\L')
    else:
      add(self.str, buf[pos])
      inc(pos)
  self.bufpos = pos

proc read_string(self: var Parser): GeneValue =
  discard self.parse_string()
  if self.error != ErrNone:
    raise newException(ParseError, "read_string failure: " & $self.error)
  result = new_gene_string_move(self.str)
  self.str = ""

proc read_quoted_internal(self: var Parser, quote_name: string): GeneValue =
  let quoted = self.read()
  result = GeneValue(kind: GeneGene, gene: Gene())
  result.gene.type = new_gene_symbol(quote_name)
  result.gene.data = @[quoted]

proc read_quoted(self: var Parser): GeneValue =
  return self.read_quoted_internal("quote")

# proc read_quasiquoted(self: var Parser): GeneValue =
#   return self.read_quoted_internal("quasiquote")

# proc read_unquoted(self: var Parser): GeneValue =
#   return self.read_quoted_internal("unquote")

proc skip_block_comment(self: var Parser) =
  var pos = self.bufpos
  var buf = self.buf
  while true:
    case buf[pos]
    of '#':
      if buf[pos-1] == '>' and buf[pos-2] != '>':
        inc(pos)
        break
      else:
        inc(pos)
    of EndOfFile:
      break
    else:
      inc(pos)
  self.bufpos = pos
  self.str = ""

proc skip_comment(self: var Parser) =
  var pos = self.bufpos
  var buf = self.buf
  while true:
    case buf[pos]
    of '\L':
      pos = lexbase.handleLF(self, pos)
      break
    of '\c':
      pos = lexbase.handleCR(self, pos)
      break
    of EndOfFile:
      break
    else:
      inc(pos)
  self.bufpos = pos

proc read_token(self: var Parser, lead_constituent: bool): string =
  var pos = self.bufpos
  var ch = self.buf[pos]
  if lead_constituent and non_constituent(ch):
    raise new_exception(ParseError, "Invalid leading character " & ch)
  else:
    result = ""
    result.add(ch)
  while true:
    inc(pos)
    ch = self.buf[pos]
    if ch == EndOfFile or isSpaceAscii(ch) or ch == ',' or is_terminating_macro(ch):
      break
    elif non_constituent(ch):
      raise new_exception(ParseError, "Invalid constituent character: " & ch)
    result.add(ch)
  self.bufpos = pos

proc read_character(self: var Parser): GeneValue =
  var pos = self.bufpos
  let ch = self.buf[pos]
  if ch == EndOfFile:
    raise new_exception(ParseError, "EOF while reading character")

  result = GeneValue(kind: GeneChar)
  let token = self.read_token(false)
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

proc skip_ws(self: var Parser) =
  # commas are whitespace in gene collections
  var buf = self.buf
  while true:
    case buf[self.bufpos]
    of ' ', '\t', ',':
      inc(self.bufpos)
    of '\c':
      self.bufpos = lexbase.handleCR(self, self.bufpos)
      buf = self.buf
    of '\L':
      self.bufpos = lexbase.handleLF(self, self.bufpos)
      buf = self.buf
    of '#':
      case buf[self.bufpos + 1]:
      of ' ', '!', '\r', '\n':
        self.skip_comment()
      of '<':
        self.skip_block_comment()
      else:
        break
    else:
      break

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

proc read_gene_type(self: var Parser): GeneValue =
  var delimiter = ')'
  # the bufpos should be already be past the opening paren etc.
  var count = 0
  while true:
    self.skip_ws()
    var pos = self.bufpos
    let ch = self.buf[pos]
    if ch == EndOfFile:
      let msg = "EOF while reading list $# $# $#"
      raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))

    if ch == delimiter:
      # Do not increase position because we need to read other components in Gene
      # inc(pos)
      # p.bufpos = pos
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      self.bufpos = pos
      result = m(self)
      if result != nil:
        inc(count)
        break
    else:
      result = self.read()
      if result != nil:
        inc(count)
        break

proc read_map(self: var Parser, part_of_gene: bool): OrderedTable[string, GeneValue] =
  var ch: char
  var key: string
  var state = PropState.PropKey
  while true:
    self.skip_ws()
    ch = self.buf[self.bufpos]
    if ch == EndOfFile:
      raise new_exception(ParseError, "EOF while reading Gene")
    elif ch == ']' or (part_of_gene and ch == '}') or (not part_of_gene and ch == ')'):
      raise new_exception(ParseError, "Unmatched delimiter: " & self.buf[self.bufpos])
    case state:
    of PropKey:
      if ch == '^':
        self.bufPos.inc()
        if self.buf[self.bufPos] == '^':
          self.bufPos.inc()
          key = self.read_token(false)
          result[key] = GeneTrue
        elif self.buf[self.bufPos] == '!':
          self.bufPos.inc()
          key = self.read_token(false)
          result[key] = GeneFalse
        else:
          key = self.read_token(false)
          state = PropState.PropValue
      elif part_of_gene:
        # Do not consume ')'
        # if ch == ')':
        #   self.bufPos.inc()
        return
      elif ch == '}':
        self.bufPos.inc()
        return
      else:
        raise new_exception(ParseError, "Expect key at " & $self.bufpos & " but found " & self.buf[self.bufpos])
    of PropState.PropValue:
      if ch == EndOfFile or ch == '^':
        raise new_exception(ParseError, "Expect value for " & key)
      elif part_of_gene:
        if ch == ')':
          raise new_exception(ParseError, "Expect value for " & key)
      elif ch == '}':
        raise new_exception(ParseError, "Expect value for " & key)
      state = PropState.PropKey
      result[key] = self.read_internal()

proc read_delimited_list(self: var Parser, delimiter: char, is_recursive: bool): DelimitedListResult =
  # the bufpos should be already be past the opening paren etc.
  var list: seq[GeneValue] = @[]
  var in_gene = delimiter == ')'
  var map_found = false
  var count = 0
  while true:
    self.skip_ws()
    var pos = self.bufpos
    let ch = self.buf[pos]
    if ch == EndOfFile:
      let msg = "EOF while reading list $# $# $#"
      raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))

    if in_gene and ch == '^':
      if map_found:
        let msg = "properties found in wrong place while reading list $# $# $#"
        raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))
      else:
        map_found = true
        result.map = self.read_map(true)
        continue

    if ch == delimiter:
      inc(pos)
      self.bufpos = pos
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      self.bufpos = pos
      let node = m(self)
      if node != nil:
        inc(count)
        list.add(node)
    else:
      let node = self.read_internal()
      if node != nil:
        inc(count)
        list.add(node)

  result.list = list

proc add_line_col(self: var Parser, node: var GeneValue): void =
  discard
  # node.line = self.line_number
  # node.column = self.getColNumber(self.bufpos)

proc read_gene(self: var Parser): GeneValue =
  result = GeneValue(kind: GeneGene, gene: Gene())
  #echo "line ", getCurrentLine(p), "lineno: ", p.line_number, " col: ", getColNumber(p, p.bufpos)
  #echo $get_current_line(p) & " LINENO(" & $p.line_number & ")"
  self.add_line_col(result)
  result.gene.type = self.read_gene_type()
  var result_list = self.read_delimited_list(')', true)
  result.gene.props = result_list.map
  result.gene.data = result_list.list

proc read_map(self: var Parser): GeneValue =
  result = GeneValue(kind: GeneMap)
  let map = self.read_map(false)
  result.map = map

proc read_vector(self: var Parser): GeneValue =
  result = GeneValue(kind: GeneVector)
  let list_result = self.read_delimited_list(']', true)
  result.vec = list_result.list

proc read_set(self: var Parser): GeneValue =
  result = GeneValue(
    kind: GeneSet,
    set: OrderedSet[GeneValue](),
  )
  let list_result = self.read_delimited_list(']', true)
  for item in list_result.list:
    result.set.incl(item)

proc read_regex(self: var Parser): GeneValue =
  var pos = self.bufpos
  var buf = self.buf
  while true:
    case buf[pos]
    of '\0':
      self.error = ErrRegexEndExpected
    of '/':
      inc(pos)
      break;
    of '\\':
      case buf[pos+1]
      of '\\', '/':
        add(self.str, buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(self.str, '\b')
        inc(pos, 2)
      of 'f':
        add(self.str, '\b')
        inc(pos, 2)
      of 'n':
        add(self.str, '\L')
        inc(pos, 2)
      of 'r':
        add(self.str, '\C')
        inc(pos, 2)
      of 't':
        add(self.str, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parse_escaped_utf16(buf, pos)
        if r < 0:
          self.error = ErrInvalidToken
          break
        # deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if buf[pos] & buf[pos + 1] != "\\u":
            self.error = ErrInvalidToken
            break
          inc(pos, 2)
          var s = parse_escaped_utf16(buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            self.error = ErrInvalidToken
            break
        add(self.str, toUTF8(Rune(r)))
      else:
        # don't bother with the Error
        add(self.str, buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(self, pos)
      buf = self.buf
      add(self.str, '\c')
    of '\L':
      pos = lexbase.handleLF(self, pos)
      buf = self.buf
      add(self.str, '\L')
    else:
      add(self.str, buf[pos])
      inc(pos)
  self.bufpos = pos
  result = GeneValue(kind: GeneRegex, regex: self.str)

proc read_unmatched_delimiter(self: var Parser): GeneValue =
  raise new_exception(ParseError, "Unmatched delimiter: " & self.buf[self.bufpos])

# proc read_discard(self: var Parser): GeneValue =
#   discard self.read()
#   result = nil

proc read_dispatch(self: var Parser): GeneValue =
  let ch = self.buf[self.bufpos]
  let m = dispatch_macros[ch]
  if m == nil:
    self.bufpos -= 1
    var token = self.read_token(false)
    result = interpret_token(token)
  else:
    self.bufpos += 1
    result = m(self)

proc init_macro_array() =
  macros['"'] = read_string
  macros[':'] = read_quoted
  macros['\''] = read_character
  # macros['`'] = read_quasi_quoted
  # macros['~'] = read_unquoted
  macros['#'] = read_dispatch
  macros['('] = read_gene
  macros['{'] = read_map
  macros['['] = read_vector
  macros[')'] = read_unmatched_delimiter
  macros[']'] = read_unmatched_delimiter
  macros['}'] = read_unmatched_delimiter

proc init_dispatch_macro_array() =
  dispatch_macros['['] = read_set
  # dispatch_macros['_'] = read_discard
  dispatch_macros['/'] = read_regex

proc init_readers() =
  init_macro_array()
  init_dispatch_macro_array()

init_readers()

proc open*(self: var Parser, input: Stream, filename: string) =
  lexbase.open(self, input)
  self.filename = filename
  self.str = ""

proc close*(self: var Parser) {.inline.} =
  lexbase.close(self)

# proc get_line(self: Parser): int {.inline.} =
#   result = self.line_number

# proc get_column(self: Parser): int {.inline.} =
#   result = self.get_col_number(self.bufpos)

# proc get_filename(self: Parser): string =
#   result = self.filename

proc parse_number(self: var Parser): TokenKind =
  result = TokenKind.TkEof
  var pos = self.bufpos
  var buf = self.buf
  if (buf[pos] == '-') or (buf[pos] == '+'):
    add(self.str, buf[pos])
    inc(pos)
  if buf[pos] == '.':
    add(self.str, "0.")
    inc(pos)
    result = TkFloat
  else:
    result = TkInt
    while buf[pos] in Digits:
      add(self.str, buf[pos])
      inc(pos)
    if buf[pos] == '.':
      add(self.str, '.')
      inc(pos)
      result = TkFloat
  # digits after the dot
  while buf[pos] in Digits:
    add(self.str, buf[pos])
    inc(pos)
  if buf[pos] in {'E', 'e'}:
    add(self.str, buf[pos])
    inc(pos)
    result = TkFloat
    if buf[pos] in {'+', '-'}:
      add(self.str, buf[pos])
      inc(pos)
    while buf[pos] in Digits:
      add(self.str, buf[pos])
      inc(pos)
  self.bufpos = pos

proc read_number(self: var Parser): GeneValue =
  var num_result = self.parse_number()
  let opts = self.options
  case num_result
  of TkEof:
    if opts.eof_is_error:
      raise new_exception(ParseError, "EOF while reading")
    else:
      result = nil
  of TkInt:
    if self.buf[self.bufpos] == '/':
      if not isDigit(self.buf[self.bufpos+1]):
        let e = err_info(self)
        raise new_exception(ParseError, "Error reading a ratio: " & $e)
      var numerator = new_gene_int(self.str)
      inc(self.bufpos)
      self.str = ""
      var denom_tok = parse_number(self)
      if denom_tok == TkInt:
        var denom = new_gene_int(self.str)
        result = new_gene_ratio(numerator.int, denom.int)
      else:
        raise new_exception(ParseError, "Error reading a ratio: " & self.str)
    else:
      result = new_gene_int(self.str)
  of TkFloat:
    result = new_gene_float(self.str)
  of TkError:
    raise new_exception(ParseError, "Error reading a number: " & self.str)
  else:
    raise new_exception(ParseError, "Error reading a number (?): " & self.str)

proc read_internal(self: var Parser): GeneValue =
  setLen(self.str, 0)
  self.skip_ws()
  let ch = self.buf[self.bufpos]
  let opts = self.options
  var token: string
  case ch
  of EndOfFile:
    if opts.eof_is_error:
      let position = (self.line_number, self.get_col_number(self.bufpos))
      raise new_exception(ParseError, "EOF while reading " & $position)
    else:
      self.token = TkEof
      return opts.eof_value
  of '0'..'9':
    return read_number(self)
  elif is_macro(ch):
    let m = macros[ch] # save line:col metadata here?
    inc(self.bufpos)
    return m(self)
  elif ch in ['+', '-']:
    if isDigit(self.buf[self.bufpos + 1]):
      return self.read_number()
    else:
      token = self.read_token(false)
      result = interpret_token(token)
      return result

  token = self.read_token(true)
  if opts.suppress_read:
    result = nil
  else:
    result = interpret_token(token)

proc read_document_properties(self: var Parser) =
  if self.document_props_done:
    return
  else:
    self.document_props_done = true
  self.skip_ws()
  var ch = self.buf[self.bufpos]
  if ch == '^':
    self.document.props = self.read_map(true)

proc read*(self: var Parser): GeneValue =
  self.read_document_properties()
  result = self.read_internal()

proc read*(self: var Parser, s: Stream, filename: string): GeneValue =
  self.open(s, filename)
  defer: self.close()
  result = self.read()

proc read*(self: var Parser, buffer: string): GeneValue =
  var s = new_string_stream(buffer)
  self.open(s, "<input>")
  defer: self.close()
  result = self.read()

proc read_all*(self: var Parser, buffer: string): seq[GeneValue] =
  var s = new_string_stream(buffer)
  self.open(s, "<input>")
  defer: self.close()
  self.read_document_properties()
  var node = self.read_internal()
  while node != nil:
    result.add(node)
    self.skip_ws()
    if self.buf[self.bufpos] == EndOfFile:
      break
    else:
      node = self.read_internal()

proc read_document*(self: var Parser, buffer: string): GeneDocument =
  self.document.data = self.read_all(buffer)
  return self.document
