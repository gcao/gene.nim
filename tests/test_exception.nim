import gene/types

import ./helpers

# Native Nim exception vs Gene exception:
# Nim exceptions can be accessed from nim/ namespace
# Nim exceptions should be translated to Gene exceptions eventually
# Gene core exceptions are defined in gene/ namespace
# Gene exceptions share same Nim class: GeneException
# For convenience purpose all exception classes like gene/XyzException are aliased as XyzException

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

test_core """
  (try
    (throw)
    1
  catch _
    2
  )
""", 2
