import times, os

import gene/vm_types
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
