---
labels:
- 'Stage-Alpha'
summary: Add "XEP-0203 Delayed Delivery"-tags to every message stanza
...

Introduction
============

This module adds "Delayed Delivery"-tags to every message stanza passing
the server containing the current time on that server.

This makes remote clients aware of when Prosody received this message, which
could be different from the time at which the client actually sent it.

Compatibility
=============

  ----- -----------------------------------------------------
  0.10  Works
  ----- -----------------------------------------------------


Clients
=======

Clients that support XEP-0203 (among others):

-   Gajim
-   Conversations
-   Yaxim
