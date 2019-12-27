
This module manages the creation and consumption of invite codes for the
host(s) it is loaded onto. It currently does not expose any admin/user-facing
functionality (though in the future it will probably gain a way to view/manage
pending invites).

Other modules can use the API from this module to create invite tokens which
can be used to e.g. register accounts or create automatic subscription approvals.

# Configuration

`` {.lua}
-- Configure the number of seconds a token is valid for (default 7 days)
invite_expiry = 86400 * 7
```

Note that all modules that use this API will automatically load this module,
so adding it to modules_enabled is generally not necessary.

# Compatibility

0.11 and later.
