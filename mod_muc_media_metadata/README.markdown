# Introduction

This module adds additional metadata to media shared in a MUC. This can help clients
make decisions and provide better UI and enhanced privacy, by knowing things like file
size without needing to make external network requests.

# Configuring

## Enabling

``` {.lua}
Component "rooms.example.net" "muc"
modules_enabled = {
    "muc_media_metadata";
}
```

## Settings

There are no configuration options for this module.

# Developers

Example stanza:

```
<message from="test@rooms.example.com/matthew" id="9f45a784-5e5b-4db5-a9b3-8ea1d7c1162d" type="groupchat">
  <body>https://matthewwild.co.uk/share.php/70334772-ff74-439b-8173-a71e40ca28db/mam-flow.png</body>
  <x xmlns="jabber:x:oob">
    <url>https://matthewwild.co.uk/share.php/70334772-ff74-439b-8173-a71e40ca28db/mam-flow.png</url>
    <metadata xmlns="https://prosody.im/protocol/media-metadata#0">
      <bytes>15690</bytes>
      <type>image/png</type>
      <blurhash>LEHV6nWB2yk8pyo0adR*.7kCMdnj</blurhash>
    </metadata>
  </x>
</message>
```
