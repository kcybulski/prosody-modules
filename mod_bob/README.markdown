---
summary: Cache Bits of Binary on MUC services
---

Description
===========

This module extracts cid: URIs (as defined in XEP-0231) from messages, and
replies with their content whenever another client asks for the actual data.

Usage
=====

```lua
Component "rooms.example.org" "muc"
	modules_enabled = {
		"bob";
		...
	}
```
