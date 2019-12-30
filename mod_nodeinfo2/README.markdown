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

Set the `nodeinfo2_expose_posts` option to false if you don’t want to expose
statistics about the amount of messages being exchanged by your users:
```
nodeinfo2_expose_posts = false
```

This module depends on [mod\_http](https://prosody.im/doc/http), most of its
configuration actually happens in this module.

Compatibility
=============

  ----- -----------
  trunk Works
  0.11  Should work
  ----- -----------
