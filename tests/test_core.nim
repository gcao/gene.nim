import unittest

import gene/types

import ./helpers

test_core "global/String", proc(r: GeneValue) =
  check r.internal.class.name == "String"

test_core """
  ($get_class "")
""", proc(r: GeneValue) =
  check r.internal.class.name == "String"

test_core "(\"\" .class)", proc(r: GeneValue) =
  check r.internal.class.name == "String"
