import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# (throw)
# (throw message)
# (throw Exception)
# (throw Exception message)
# (throw (new Exception ...))

# (try...catch...catch...finally)
# (try...finally)
# (fn f []  # converted to (try ...)
#   ...
#   catch ExceptionX ...
#   catch _ ...
#   finally ...
# )

# test "(throw ...)":
#   var code = """
#     (throw "test")
#   """.cleanup
#   test "Interpreter / eval: " & code:
#     var interpreter = new_vm()
#     discard interpreter.eval(code)
#     # try:
#     #   discard interpreter.eval(code)
#     #   check false
#     # except:
#     #   discard

test_interpreter """
  (try
    (not_allowed)
    1
  catch _
    2
  )
""", 2
