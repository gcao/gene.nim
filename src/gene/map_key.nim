import tables, hashes

type
  MapKey* = distinct int

var Keys*: seq[string] = @[]
var KeyMapping* = Table[string, MapKey]()

converter to_key*(i: int): MapKey {.inline.} =
  result = cast[MapKey](i)

proc add_key*(s: string): MapKey {.inline.} =
  Keys.add(s)
  result = Keys.len
  KeyMapping[s] = result

converter to_key*(s: string): MapKey {.inline.} =
  if KeyMapping.has_key(s):
    result = KeyMapping[s]
  else:
    result = add_key(s) 

proc to_s*(self: MapKey): string {.inline.} =
  result = Keys[cast[int](self)]

proc `%`*(self: MapKey): string =
  result = Keys[cast[int](self)]

converter to_strings*(self: seq[MapKey]): seq[string] {.inline.} =
  for k in self:
    result.add(k.to_s)

converter to_keys*(self: seq[string]): seq[MapKey] {.inline.} =
  for item in self:
    result.add(item.to_key)

# proc `==`*(this, that: MapKey): bool {.inline.} =
#   result = cast[int](this) == cast[int](that)

proc hash*(self: MapKey): Hash {.inline.} =
  result = cast[int](self)

let EMPTY_STRING_KEY*         = add_key("")
let SELF_KEY*                 = add_key("self")
let METHOD_KEY*               = add_key("method")
let COND_KEY*                 = add_key("cond")
let THEN_KEY*                 = add_key("then")
let ELSE_KEY*                 = add_key("else")
let NAMES_KEY*                = add_key("names")
let MODULE_KEY*               = add_key("module")
let PKG_KEY*                  = add_key("pkg")
let ROOT_NS_KEY*              = add_key("<root>")
let ASYNC_KEY*                = add_key("async")
let ARGS_KEY*                 = add_key("args")
let TYPE_KEY*                 = add_key("type")
let TOGGLE_KEY*               = add_key("toggle")
let MULTIPLE_KEY*             = add_key("multiple")
let REQUIRED_KEY*             = add_key("required")
let DEFAULT_KEY*              = add_key("default")
let DISCARD_KEY*              = add_key("discard")
let STDERR_KEY*               = add_key("stderr")
let DECORATOR_KEY*            = add_key("decorator")
let ENUM_KEY*                 = add_key("enum")
let RANGE_KEY*                = add_key("range")
let DO_KEY*                   = add_key("do")
let LOOP_KEY*                 = add_key("loop")
let WHILE_KEY*                = add_key("while")
let FOR_KEY*                  = add_key("for")
let BREAK_KEY*                = add_key("break")
let CONTINUE_KEY*             = add_key("continue")
let IF_KEY*                   = add_key("if")
let NOT_KEY*                  = add_key("not")
let VAR_KEY*                  = add_key("var")
let THROW_KEY*                = add_key("throw")
let TRY_KEY*                  = add_key("try")
let FN_KEY*                   = add_key("fn")
let MACRO_KEY*                = add_key("macro")
let RETURN_KEY*               = add_key("return")
let ASPECT_KEY*               = add_key("aspect")
let BEFORE_KEY*               = add_key("before")
let AFTER_KEY*                = add_key("after")
let NS_KEY*                   = add_key("before")
let IMPORT_KEY*               = add_key("import")
let IMPORT_NATIVE_KEY*        = add_key("import_native")
let APPLICATION_CLASS_KEY*    = add_key("Application")
let PACKAGE_CLASS_KEY*        = add_key("Package")
let CLASS_CLASS_KEY*          = add_key("Class")
let FUTURE_CLASS_KEY*         = add_key("Future")
let FILE_CLASS_KEY*           = add_key("File")
let NIL_CLASS_KEY*            = add_key("Nil")
let BOOL_CLASS_KEY*           = add_key("Bool")
let INT_CLASS_KEY*            = add_key("Int")
let CHAR_CLASS_KEY*           = add_key("Char")
let STRING_CLASS_KEY*         = add_key("String")
let SYMBOL_CLASS_KEY*         = add_key("Symbol")
let COMPLEX_SYMBOL_CLASS_KEY* = add_key("ComplexSymbol")
let ARRAY_CLASS_KEY*          = add_key("Array")
let MAP_CLASS_KEY*            = add_key("Map")
let SET_CLASS_KEY*            = add_key("Set")
let GENE_CLASS_KEY*           = add_key("Gene")
let REGEX_CLASS_KEY*          = add_key("Regex")
let RANGE_CLASS_KEY*          = add_key("Range")
let DATE_CLASS_KEY*           = add_key("Date")
let DATETIME_CLASS_KEY*       = add_key("DateTime")
let TIME_CLASS_KEY*           = add_key("Time")
let TIMEZONE_CLASS_KEY*       = add_key("Timezone")
