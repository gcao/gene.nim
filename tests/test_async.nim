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

test_interpreter """
  (async 1)
""", proc(r: GeneValue) =
  check r.internal.kind == GeneFuture

test_core """
  (async (throw))   # Exception will have to be caught by await, or on_failure
  1
""", 1

# test_core """
#   (var future (async (throw)))
#   (var a 0)
#   (future .on_success (-> (a = 1)))
#   (future .on_failure (-> (a = 2)))
#   a
# """, 2

test_core """
  (var future
    # async will return the internal future object
    (async (gene/sleep_async 50))
  )
  (var a 0)
  (future .on_success (-> (a = 1)))
  a   # future has not finished yet
""", 0

test_core """
  (var future
    (async (gene/sleep_async 50))
  )
  (var a 0)
  (future .on_success (-> (a = 1)))
  (gene/sleep 100)
  a   # future should have finished
""", 1

test_core """
  (try
    (await
      (async (throw AssertionError))
    )
    1
  catch AssertionError
    2
  catch _
    3
  )
""", 2

test_interpreter """
  (await (async 1))
""", 1

test_core """
  (var a)
  (var future (gene/sleep_async 50))
  (future .on_success (->
    (a = 1)
  ))
  (await future)
  a
""", 1
