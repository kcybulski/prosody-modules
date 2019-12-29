---
description: 
labels: 'Stage-Alpha'
---

Introduction
============

This module exposes a [nodeinfo2](https://git.feneas.org/jaywink/nodeinfo2)
.well-known URL for use e.g. from
[the-federation.info](https://the-federation.info).

Configuration
=============

Enable the `nodeinfo` module in your global `modules_enabled` section:
```
modules_enabled = {
    ...
    "nodeinfo2"
    ...
}
```

This module depends on [mod\_http](https://prosody.im/doc/http), all of its
configuration actually happens in this module.

Compatibility
=============

  ----- -----------
  trunk Works
  0.11  Should work
  ----- -----------
