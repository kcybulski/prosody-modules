---
labels:
- 'Stage-Stable'
summary: 'XEP-0288: Bidirectional Server-to-Server Connections'
...

Introduction
============

This module implements [XEP-0288: Bidirectional Server-to-Server
Connections](http://xmpp.org/extensions/xep-0288.html). It allows
servers to use a single connection for sending stanzas to each other,
instead of two connections (one for stanzas in each direction).

Install and enable it like any other module. It has no configuration.

Compatibility
=============

  ------- --------------------------
  trunk   Bidi available natively with [mod_s2s_bidi][doc:modules:mod_s2s_bidi]
  0.11    Works
  0.10    Works
  0.9     Works
  0.8     Works (use the 0.8 repo)
  ------- --------------------------
