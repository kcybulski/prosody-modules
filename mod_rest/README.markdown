---
labels:
- 'Stage-Alpha'
summary: RESTful XMPP API
---

# Introduction

This is yet another RESTful API for sending stanzas via Prosody.

# Usage

Note that there is currently **no authentication**, so be careful with
exposing the API endpoint to the Internet.

## Enabling

``` {.lua}
Component "rest.example.net" "rest"
```

## Sending stanzas

The API endpoint becomes available at the path `/rest`, so the full URL
will be something like `https://your-prosody.example:5281/rest`.

To try it, simply `curl` an XML stanza payload:

``` {.sh}
curl https://prosody.example:5281/rest \
    -H 'Content-Type: application/xmpp+xml' \
    --data-binary '<message type="chat" to="user@example.org">
            <body>Hello!</body>
        </body>'
```

The `Content-Type` **MUST** be `application/xmpp+xml`.

### Replies

A POST containing an `<iq>` stanza automatically wait for the reply,
long-polling style.

``` {.sh}
curl https://prosody.example:5281/rest \
    -H 'Content-Type: application/xmpp+xml' \
    --data-binary '<iq type="get" to="example.net">
            <ping xmlns="urn:xmpp:ping"/>
        </iq>'
```

# Compatibility

Requires Prosody trunk / 0.12
