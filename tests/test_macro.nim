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

test_interpreter """
  (macro m b
    b
  )
  (m a)
""", new_gene_symbol("a")

test_interpreter """
  (var a 1)
  (macro m []
    ($caller_eval :a)
  )
  (m)
""", 1

test_interpreter """
  (var a 1)
  (macro m b
    ($caller_eval b)
  )
  (m a)
""", 1
