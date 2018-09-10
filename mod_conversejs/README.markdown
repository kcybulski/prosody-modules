---
depends:
- 'mod\_bosh'
- 'mod\_websocket'
provides:
- http
title: 'mod\_conversejs'
---

Introduction
============

This module serves a small snippet of HTML that loads
[Converse.js](https://conversejs.org/), configured to work with the
VirtualHost that it is loaded onto.

Configuration
=============

The module uses general Prosody options for basic configuration. It
should just work after loading it.

``` {.lua}
modules_enabled = {
    -- other modules...
    "conversejs";
}
```

Authentication
--------------

[Authentication settings][doc:authentication] are used determine
whether to configure Converse.js to use `login` or `anonymous` mode.

Connection methods
------------------

It also determines the [BOSH][doc:modules:mod_bosh] and
[WebSocket][doc:modules:mod_websocket] URL automatically, see their
respective documentation for how to configure them. Both connection
methods are loaded automatically.

HTTP
----

The module is served on Prosody's default HTTP ports at the path
`/conversejs`. More details on configuring HTTP modules in Prosody can
be found in our [HTTP documentation](http://prosody.im/doc/http).

Other
-----

To pass [other Converse.js
options](https://conversejs.org/docs/html/configuration.html), or
override the derived settings, one can set `conversejs_options` like
this:

``` {.lua}
conversejs_options = {
    debug = true;
    view_mode = "fullscreen";
}
```

Note that the following options are automatically provided, and
**overriding them may cause problems**:

-   `authentication` *based on Prosodys authentication settings*
-   `jid` *the current `VirtualHost`*
-   `bosh_service_url`
-   `websocket_url` *if `mod_websocket` is available*

Compatibility
=============

Should work with Prosody 0.9 and later. Websocket support requires 0.10.
