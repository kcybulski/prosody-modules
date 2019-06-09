---
labels:
- 'Stage-Alpha'
summary: 'XEP-XXXX: Web Push'
---

Introduction
============

::: {.alert .alert-danger}
**This module is terribly untested and will only work with Firefox as it's
missing payload encryption. Other vendors require it all the time. Public and
private keys are also statically set in it.**
:::

This is an implementation of the server bits of [XEP-XXXX: Web Push].

It allows web clients to register a "push server" which is notified about new
messages while the user is offline, disconnected or the session is hibernated
by [mod_smacks].

Push servers are provided by browser vendors.

This module is heavily based on [mod_cloud_notify].

Details
=======

[Push API](https://w3c.github.io/push-api/) is a specification by the W3C that
is essentially the same principle as Mobile OS vendors' Push notification
systems. It is implemented by most browsers vendors except Safari on iOS
(mobile).

For more information, see:
- https://developer.mozilla.org/en-US/docs/Web/API/Push_API
- https://developers.google.com/web/ilt/pwa/introduction-to-push-notifications

Compared to [XEP-0357: Push Notifications], Web Push doesn't need an App
Server.

The general flow for subscription is:
- XMPP server generate ECDH keypair, publishes public key
- XMPP client generates an ECDH keypair
- XMPP client fetches server public key
- XMPP client subscribes to browser Push server using the Web Push API, and
  gets back an HTTP endpoint
- XMPP client enables Push notifications telling the server the HTTP endpoint,
  and its public key

The flow for notifications is as follow:
- XMPP server receives an _important_[^1] message
- XMPP server generates something something JWT + signature with ECDH key
- XMPP server can optionally include payload encrypted for the client
- XMPP server initiates HTTP POST request to the Push server
- Push server sends notification to web browser

Configuration
=============

  Option                               Default           Description
  ------------------------------------ ----------------- -------------------------------------------------------------------------------------------------------------------
  `push_notification_important_body`   `New Message!`    The body text to use when the stanza is important (see above), no message body is sent if this is empty
  `push_max_devices`                   `5`               The number of allowed devices per user (the oldest devices are automatically removed if this threshold is reached)

There are privacy implications for enabling these options because
plaintext content and metadata will be shared with centralized servers
(the pubsub node) run by arbitrary app developers.

Installation
============

Same as any other module.

Configuration
=============

Configured in-band by supporting clients.

[^1]: As defined in mod_cloud_notify, or mod_csi_simple.
