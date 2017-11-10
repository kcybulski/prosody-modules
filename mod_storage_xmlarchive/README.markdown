---
labels:
- 'Stage-Beta'
- 'Type-Storage'
- ArchiveStorage
summary: XML file based archive storage
---

Introduction
============

This module implements stanza archives using files, similar to the
default "internal" storage.

Configuration
=============

To use this with [mod\_mam] add this to your config:

``` lua
storage = {
    archive2 = "xmlarchive"
}
```

To use it with [mod\_mam\_muc] or [mod\_http\_muc\_log]:

``` lua
storage = {
    muc_log = "xmlarchive"
}
```

Refer to [Prosodys data storage documentation][doc:storage] for more
information.

Note that this module does not implement the "keyval" storage method and
can't be used by anything other than archives.

Compatibility
=============

  ------ ---------------
  0.10   Works
  0.9    Should work
  0.8    Does not work
  ------ ---------------

Conversion to or from internal storage
--------------------------------------

This module stores data in a way that overlaps with the more recent
archive support in `mod_storage_internal`, meaning e.g. [mod_migrate]
will not be able to cleanly convert to or from the `xmlarchive` format.

To mitigate this, an migration command has been added to
`mod_storage_xmlarchive`:

``` bash
prosodyctl mod_storage_xmlarchive convert $DIR internal $STORE $JID
```

Where `$DIR` is `to` or `from`, `$STORE` is e.g. `archive` or `archive2`
for MAM and `muc_log` for MUC logs. Finally, `$JID` is the JID of the
user or MUC room to me migrated, which can be repeated.
