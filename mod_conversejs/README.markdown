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

The module itself has no configuration. It uses
[authentication settings][doc:authentication] to determine whether to
configure Converse.js to use `login` or `anonymous` mode.

It also determines the [BOSH][mod_bosh] and [WebSocket][mod_websocket]
URL automatically, see their respective documentation for how to configure
them.

See Prosodys [HTTP configuration][doc:http] for HTTP related options.


