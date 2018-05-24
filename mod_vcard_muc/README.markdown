Introduction
============

This module adds the ability to set vCard for MUC rooms. One of the most common use case is to be able to define an avatar for your own MUC room.

Usage
=====

Add "vcard\_muc" to your modules\_enabled list:

``` {.lua}
Component "conference.example.org" "muc"
modules_enabled = {
  "vcard_muc",
}
```

Compatibility
=============

  ----- -------------
  trunk Works
  0.10  Should work
  0.9   Should work
  ----- -------------


