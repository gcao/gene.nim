import unittest

import gene/types

import ./helpers

# test_interpreter "gene", proc(r: GeneValue) =
#   check r.internal.ns.name == "gene"
# test_interpreter "genex", proc(r: GeneValue) =
#   check r.internal.ns.name == "genex"

test_core "gene/String", proc(r: GeneValue) =
  check r.internal.class.name == "String"

test_core """
  ($get_class "")
""", proc(r: GeneValue) =
  check r.internal.class.name == "String"

test_core "(\"\" .class)", proc(r: GeneValue) =
  check r.internal.class.name == "String"
