This module compares the memory usage reported by Lua before and after
each event and reports it to the log if it exceeds the configuration
setting `log_memory_threshold` (in bytes).

``` lua
log_memory_threshold = 20*1024
```

Prosody runs on Lua which uses automatic memory management with garbage
collection, so the numbers reported by this module are very likely to be
useless for the purpose of identifying memory leaks. Large, but
temporary, increases in memory usage can however highlight other kinds
of performance problems and sometimes even provide hits for where to
look for memory leaks.
