import unittest, strutils

import gene/arg_parser

# Command line arguments matching
#
# Program:   program, usually the first argument
# Option:    prefixed with "-" or "--"
# Primary:
# Secondary: after "--"
#
# Required vs optional
# Toggle vs value expected
# Single vs multiple values
#
# -l --long
# -l x -l y -l z
# xyz
# -- x y z

# Input:   seq[string] or string(raw arguments string)
# Pattern:
# Result:

proc test_args*(input: string, callback: proc(input: string)) =
  test "Command line arguments: " & input:
    callback input

test_args "", proc(input: string) =
  var m = new_matcher()
  var r = m.match(input.split(" "))
  check r.kind == AmSuccess
