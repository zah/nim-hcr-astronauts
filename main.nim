import space
import os
import hotcodereloading

if real_init():
  while main_loop():
    if hasAnyModuleChanged():
      sleep(100) # prevent filesystem races
      performCodeReload()
  cleanup()

