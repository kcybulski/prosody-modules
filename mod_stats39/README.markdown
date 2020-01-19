This module provides **public** access to Prosodys
[internal statistics][doc:statistics] trough the
[XEP-0039: Statistics Gathering] protocol. This is a simple protocol
that returns triplets of name, unit and value for each know statistic
collected by Prosody. The names used are the internal names assigned by
modules or statsmanager, names from the registry are **not** used.

# Configuration

Enabled as usual by adding to [`modules_enabled`][doc:modules_enabled]:

```lua
-- Enable Prosodys internal statistics gathering
statistics = "internal"

-- and enable the module
modules_enabled = {
    -- other modules
    "stats39";
}
```

# Usage


## Example

Statistics can be queried from the XML console of clients that have one:

```xml
C:
<iq type="get" to="example.com" id="dTMERjt5">
  <query xmlns="http://jabber.org/protocol/stats"/>
</iq>

S:
<iq type="result" to="example.com" id="dTMERjt5">
  <query xmlns="http://jabber.org/protocol/stats">
  </query>
</iq>
```

