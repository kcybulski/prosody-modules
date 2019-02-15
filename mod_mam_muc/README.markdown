---
labels:
- 'Stage-Alpha'
summary: 'XEP-0313: Message Archive Management for MUC'
...

Introduction
============

This module logs the conversation of chatrooms running on the server to
Prosody's archive storage. To access them you will need a client with
support for [XEP-0313: Message Archive Management] **version 0.5** or
a module such as [mod_http_muc_log].

Usage
=====

First copy the module to the prosody plugins directory.

Then add "mam\_muc" to your modules\_enabled list:

``` {.lua}
Component "conference.example.org" "muc"
modules_enabled = {
  "mam_muc",
}
```

mod\_mam\_muc needs an archive-capable storage module, see
[Prosodys storage documentation][doc:storage] for how to select one.
The store is called "muc\_log".

Configuration
=============

Logging needs to be enabled for each room in the room configuration
dialog.

``` {.lua}
muc_log_by_default = true; -- Enable logging by default (can be disabled in room config)

muc_log_all_rooms = false; -- set to true to force logging of all rooms

-- This is the largest number of messages that are allowed to be retrieved when joining a room.
max_history_messages = 20;
```

Compatibility
=============

  ------- ---------------------------------------------------------------------
  trunk   Use mod\_muc\_mam (included with Prosody)
  0.11    Use mod\_muc\_mam (included with Prosody)
  0.10    Works partially, only XEP-0313 version 0.5 (namespace urn:xmpp:mam:1)
  0.9     Does not work
  0.8     Does not work
  ------- ---------------------------------------------------------------------

Prosody trunk (after April 2014) has a major rewrite of the MUC module,
allowing easier integration, but this module is not compatible with
that.
