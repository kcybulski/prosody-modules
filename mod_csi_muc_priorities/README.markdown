# Introduction

This module lets users specify which of the group chats they are in are
less important. This influences when
[mod_csi_simple][doc:modules:mod_csi_simple] decides to send
stanzas vs waiting until there is more to send. Users in many large
public channels might benefit from this.

# Configuration

The module is configured via ad-hoc an command called *Configure group
chat priorities* that should appear in the menus of compatible clients.

The command presents a form that accepts a list of XMPP addresses.
Currently there is a single priority, *Lower priority*, which is
suitable for e.g. noisy public channels. mod_csi_simple considers
groupchat messages important by default on the assumptions that smaller
and more important private chats are more common among most users.

A message of type groupchat from an address in this list will not be
considered important enough to send it to an inactive client, unless it
is from the current user or mentions of their nickname. **Note** that
mention support require the separate module [mod_track_muc_joins]
to also be loaded.
