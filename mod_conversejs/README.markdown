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

-   `authentication` *based on Prosody's authentication settings*
-   `jid` *the current `VirtualHost`*
-   `bosh_service_url`
-   `websocket_url` *if `mod_websocket` is available*

Loading resources
-----------------

By default the module will load the main script and CSS from cdn.conversejs.org. For privacy or performance
reasons you may want to load the scripts from somewhere else, simply use the conversejs_cdn option:

``` {.lua}
conversejs_cdn = "https://cdn.example.com"
```

To select a specific version of Converse.js, you may override the version:

``` {.lua}
conversejs_version = "4.0.1"
```

Note that versions other than the default may not have been tested with this module, and may include incompatible changes.

Finally, if you can override all of the above and just specify links directly to the CSS and JS files:

``` {.lua}
conversejs_script = "https://example.com/my-converse.js"
conversejs_css = "https://example.com/my-converse.css"
```

Additional tags
---------------

To add additional tags to the module, such as custom CSS or scripts, you may use the conversejs_tags option:

``` {.lua}
conversejs_tags = {
        -- Load custom CSS
        [[<link rel="stylesheet" href="https://example.org/css/custom.css">]];

        -- Load libsignal-protocol.js for OMEMO support (GPLv3; be aware of licence implications)
        [[<script src="https://cdn.conversejs.org/3rdparty/libsignal-protocol.min.js"></script>]];
}
```

The example above uses the `[[` and `]]` syntax simply because it will not conflict with any embedded quotes.

Compatibility
=============

Should work with Prosody 0.9 and later. Websocket support requires 0.10.
