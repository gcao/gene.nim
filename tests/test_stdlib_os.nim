import unittest, tables, os, osproc

import gene/types
import gene/interpreter

import ./helpers

test_core """
  (env "HOME")
""", get_env("HOME")

test_core """
  (gene/File/read "tests/fixtures/test.txt")
""", "line1\nline2"

test_core """
  (gene/os/exec "pwd")
""", execCmdEx("pwd")[0]
