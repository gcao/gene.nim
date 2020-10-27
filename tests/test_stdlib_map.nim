import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core """
  ({^a 1 ^b 2} .size)
""", 2

# test_core """
#   (var sum 0)
#   ({^a 1 ^b 2} .each
#     ([_ v] -> (sum += v))
#   )
#   sum
# """, 3
