import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core "(\"abc\" .size)", 3

test_core "(\"abc\" .substr 1)", "bc"
test_core "(\"abc\" .substr -1)", "c"
test_core "(\"abc\" .substr -2 -1)", "bc"

test_core "(\"abc\" .split \"b\")", @[new_gene_string("a"), new_gene_string("c")]
