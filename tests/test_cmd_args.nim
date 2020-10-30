import unittest, strutils

import gene/arg_parser

import ./helpers

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
# -l x -l y -l z  OR -l x,y,z
# xyz
# -- x y z

# Input:   seq[string] or string(raw arguments string)
# Schema:
# Result:

# [
#   program
#   (option   ^^required ^^multiple ^type int -l --long) # "long" will be used as key
#   (argument ^^required ^^multiple ^type int name)      # "name" will be used as key
# ]

proc test_args*(schema, input: string, callback: proc(r: ArgMatchingResult)) =
  var schema = cleanup(schema)
  var input = cleanup(input)
  test schema & "\n" & input:
    var m = new_matcher()
    # m.parse(schema)
    var r = m.match(input.split(" "))
    callback r

test_args """
  [
    (option -l --long)
    (argument test)
  ]
""", """
  -l value test-value
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
