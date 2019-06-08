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
It allows clients to register a "push server" which is notified about new
messages while the user is offline, disconnected or the session is hibernated
by [mod_smacks].

Push servers are provided by browser vendors.

This module is heavily based on [mod_cloud_notify].

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
