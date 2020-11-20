import unittest

import gene/types

import ./helpers

# Support asynchronous functionality
# Depending on Nim
# Support custom asynchronous call - how?
#
# Future type
# * check status
# * report progress (optionally)
# * invoke callback on finishing
# * timeout
# * exception
# * cancellation
# * await: convert to synchronous call
#

# test_interpreter """
#   (async 1)
# """, proc(r: GeneValue) =
#   check r.internal.kind == GeneFuture
