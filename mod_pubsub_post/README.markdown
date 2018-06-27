# Introduction

Lets you easily publish data to PubSub using a HTTP POST request. The
payload can be Atom feeds, arbitrary XML, or arbitrary JSON. The type
should be indicated via the `Content-Type` header.

``` {.bash}
curl http://localhost:5280/pubsub_post/princely_musings \
    -H "Content-Type: application/json" \
    --data-binary '{"musing":"To be, or not to be: that is the question"}'
```

# Configuration

## Authentication

Authentication can be handled in two different ways.

### None

``` {.lua}
pubsub_post_actor = "superuser"
```

The module uses an internal actor that has all privileges and can always
do everything. It is strongly suggested that you do not expose this to
the Internet. *Maybe* it shouldn't be the default...

### IP

``` {.lua}
pubsub_post_actor = "request.ip"
```

Uses the IP address from the HTTP request as actor, which means this
pseudo-JID must be given a 'publisher' affiliation. This should work
nicely with the `autocreate_on_publish` setting, where the first actor
to attempt to publish to a non-existant node becomes owner of it, which
includes publishing rights.

Prosodys PubSub module supports [setting affiliations via
XMPP](https://xmpp.org/extensions/xep-0060.html#owner-affiliations), in
trunk since [revision
384ef9732b81](https://hg.prosody.im/trunk/rev/384ef9732b81).

It can however be done from another plugin:

``` {.lua}
local mod_pubsub = module:depends("pubsub");
local pubsub = mod_pubsub.service;

pubsub:create("princely_musings", true);
pubsub:set_affiliation("princely_musings", true, "127.0.0.1", "publisher");
```
