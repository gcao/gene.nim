import jsffi

import gene/types
import gene/vm
import gene/interpreter

proc eval*(s: cstring): GeneValue =
  var vm = new_vm()
  vm.eval($s)

var module {.importc.}: JsObject
module.exports.eval = eval
