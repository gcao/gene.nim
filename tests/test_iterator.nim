import unittest

import gene/types
import gene/interpreter

import ./helpers

test_core """
  (var sum)
  (for v in (gene/native/props {^a 1 ^b 2})
    (sum += v)
  )
  sum
""", 3
