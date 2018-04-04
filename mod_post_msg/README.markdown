---
summary: 'Receives HTTP POST request, parses it and relays it into XMPP.'
---

Introduction
============

Sometimes it's useful to have different interfaces to access XMPP.

This is example of sending message using HTTP POST to XMPP. For sure we
need user auth information.

Example usage
-------------

    curl http://example.com:5280/msg/user -u me@example.com:mypassword -H "Content-Type: text/plain" -d "Server@host has just crashed!"

This would send a message to user\@example.com from me\@example.com

Details
=======

Payload formats
---------------

Supported formats are:

`text/plain`
:   The HTTP body is used as message `<body>`.

`application/x-www-form-urlencoded`
:   Allows more fields to be specified.

### Data fields

The form data format allow the following fields:

`to`
:   Can be used instead of having the receiver in the URL.

`type`
:   [Message type.](https://xmpp.org/rfcs/rfc6121.html#message-syntax-type)

`body`
:   Plain text message payload.

Acknowledgements
----------------

Some code originally borrowed from mod\_webpresence
