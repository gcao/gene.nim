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

test_core """
  (var file "/tmp/test.txt")
  (gene/File/write file "test")
  (gene/File/read file)
""", "test"

test_core """
  (var file (gene/File/open "tests/fixtures/test.txt"))
  (file .read)
""", "line1\nline2"
