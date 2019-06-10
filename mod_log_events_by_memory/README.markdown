This module compares the memory usage reported by Lua before and after
each event and reports it to the log if it exceeds the configuration
setting `log_memory_threshold` (in bytes).

``` lua
log_memory_threshold = 20*1024
```

