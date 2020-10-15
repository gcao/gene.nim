import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core "(\"abc\" .size)", 3

# test_core "(\"abc\" .substr 1)", "bc"