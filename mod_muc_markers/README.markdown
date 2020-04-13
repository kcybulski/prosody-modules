# Introduction

This module adds an internal Prosody API to retrieve the last received message by MUC occupants.

## Requirements

The clients must support XEP-0333, and the users to be tracked must be affiliated with the room.

Currently due to lack of clarity about which id to use in acknowledgements in XEP-0333, this module
rewrites the id attribute of stanzas to match the stanza (archive) id assigned by the MUC server.

Oh yeah, and mod_muc_mam is required (or another module that adds a stanza-id), otherwise this module
won't do anything.

# Configuring

## Enabling

``` {.lua}
Component "rooms.example.net" "muc"
modules_enabled = {
    "muc_markers";
    "muc_mam";
}
```

## Settings

There are no configuration options for this module.

# Developers

## Example usage

```
local muc_markers = module:depends("muc_markers");

function something()
	local last_received_id = muc_markers.get_user_read_marker("user@localhost", "room@conference.localhost");
end
```
