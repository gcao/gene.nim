import ./types

type
  Module* = ref ModuleObj
  ModuleObj = object of RootObj
    name: string
    methods: seq[Function]

  Class* = ref ClassObj
  ClassObj = object of ModuleObj

#################### Module ######################

#################### Class #######################
