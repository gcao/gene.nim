import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core """
  (var sum 0)
  (4 .times (i -> (sum += i)))
  sum
""", 6 # 0 + 1 + 2 + 3
