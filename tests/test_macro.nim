# import unittest

import gene/types

import ./helpers

# Macro support
#
# * A macro will generate an AST tree and pass back to the VM to execute.
#

test_interpreter """
  (macro m [a b]
    (a + b)
  )
  (m 1 2)
""", 3
