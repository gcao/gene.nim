# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
import nimprof

import times

import gene/vm
import gene/parser
import gene/interpreter

when isMainModule:
  var vm = new_vm()
  let parsed = read_all("""
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib 24)
  """)
  let start = cpuTime()
  let result = vm.eval(parsed)
  echo "Time: " & $(cpuTime() - start)
  echo result.num
