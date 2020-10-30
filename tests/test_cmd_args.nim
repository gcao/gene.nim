import unittest, strutils, tables

import gene/types
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
#   (option   ^^toggle -t "description")                 # "t" will be used as key
#   (option   ^^required ^^multiple ^type int -l --long) # "--long" will be used as key
#   (argument ^type int name "description")              # "name" will be used as key
#   (argument ^^multiple ^type int name)                 # "name" will be used as key
# ]

test_args """
  [
    (option -l --long)
    (argument test)
  ]
""", """
  -l value test-value
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 1
  check r.options["--long"] == "value"
  check r.args.len == 1
  check r.args["test"] == "test-value"
