import unittest, tables

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
    (argument first)
  ]
""", """
  -l long-value one
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 1
  check r.options["--long"] == "long-value"
  check r.args.len == 1
  check r.args["first"] == "one"

test_args """
  [
    program
    (option -l --long)
    (option ^^multiple -m)
    (argument first)
    (argument ^^multiple second)
  ]
""", """
  my-script -l long-value -m m1,m2 one two three
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.program == "my-script"
  check r.options.len == 2
  check r.options["--long"] == "long-value"
  check r.options["-m"] == @[new_gene_string("m1"), new_gene_string("m2")]
  check r.args.len == 2
  check r.args["first"] == "one"
  check r.args["second"] == @[new_gene_string("two"), new_gene_string("three")]

test_args """
  [
    (option ^type bool -b)
    (option ^type int -i)
    (option ^type int ^^multiple -m)
    (argument ^type int first)
    (argument ^type int ^^multiple second)
  ]
""", """
  -b true -i 1 -m 2,3 1 2 3
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 3
  check r.options["-b"]
  check r.options["-i"] == 1
  check r.options["-m"] == @[new_gene_int(2), new_gene_int(3)]
  check r.args.len == 2
  check r.args["first"] == 1
  check r.args["second"] == @[new_gene_int(2), new_gene_int(3)]
