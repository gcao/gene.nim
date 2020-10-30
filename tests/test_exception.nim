import unittest, tables

import gene/types

import ./helpers

# (throw)
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

# test_interpreter """
#   (try
#     (not_allowed)
#     1
#   catch _
#     2
#   )
# """, 2
