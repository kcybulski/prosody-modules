This module implements the [Server
Optimization](https://xmpp.org/extensions/xep-0410.html#serveroptimization)
part of [XEP-0410: MUC Self-Ping]

# Usage

The module is loaded on MUC components:

```lua
Component "muc.example.com" "muc"
modules_enabled = {
    "muc_ping";
}
```

# Configuration

No options.

# Compatibility

It should work with Prosody up until 0.10.x.

Prosody trunk natively supports XEP-0410 so this module is not needed.
