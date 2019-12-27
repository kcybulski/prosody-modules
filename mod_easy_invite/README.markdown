
This module allows admins and users to create invitations suitable for sharing
to potential new users/contacts.

User invitations can be created through the "New Invite" ad-hoc command. An overview
of the semantics and protocol can be found at [modernxmpp.org/client/invites](https://docs.modernxmpp.org/client/invites/).

This module depends on mod_invites to actually create and store the invitation tokens.

# Configuration

To allow users to join your server through invitations, you must
enable mod_register_ibr and set allow_registration = true, and then
also set `registration_invite_only = true` to restrict registration.

``` {.lua}
-- To allow invitation through a token, mod_register
registration_invite_only = true
```

To allow existing users of your server to send invitation links that
allow new people to join your server, you can set `allow_user_invites = true`.

If you do not wish users to invite other users to create accounts on your
server, set `allow_user_invites = false`. They will still be able to send
contact invites, but new contacts will be required to register an account
on a different server.

# Usage

Users can use the "New Invite" ad-hoc command through their client.

Admins can create registration links using prosodyctl, e.g.

```
prosodyctl mod_easy_invite example.com register
```

# Compatibility

0.11 and later.
