---
labels:
- Statistics
summary: Implementation of the Prometheus protocol
...

Description
===========

This module implements the Prometheus reporting protocol, allowing you
to collect statistics directly from Prosody into Prometheus.

See the [Prometheus documentation][prometheusconf] on the format for
more information.

[prometheusconf]: https://prometheus.io/docs/instrumenting/exposition_formats/

Configuration
=============

mod\_prometheus itself doesn’t have any configuration option, but it
requires Prosody’s [internal statistics
provider](https://prosody.im/doc/statistics#built-in_providers) to be
enabled.  You may also want to change the default collection interval
to the one your statistics consumer is using.

```lua
statistics = "internal"
statistics_interval = 15 -- in seconds
```

See also the documentation of Prosody’s [HTTP
server](https://prosody.im/doc/http), since Prometheus is an HTTP
protocol that is how you can customise its URL.  The default one being
http://localhost:5280/metrics

Compatibility
=============

  ------- -------------
  trunk   Works
  0.10    Works
  0.9     Does not work
  ------- -------------
