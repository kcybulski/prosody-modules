mod_auh_token_ldap
==================

*Prosody module allowing authentication by token and ldap as fallback.*

-----------------------------------------------------------

Introduction
============
This module allow to configure Jitsi Meet to support two authentication mechanism in one VirtualHost.
This allow for integration  Rocket.Chat (via token) and starting Jitsi Meet sessions by users authenticated by LDAP, 
and guest users still can connect to alredy existing sessions.

Details
=======

This module is simple merge of mod_auth_token [1] from prosody core modules and mod_auth_ldap [2] from community modules.
All credit go to authors of this modules. 
This is needed becose Jicofo don't support setting multiple domains in org.jitsi.jicofo.auth.URL [3].

[1] https://github.com/jitsi/lib-jitsi-meet/blob/master/doc/tokens.md#manual-plugin-configuration

[2] https://modules.prosody.im/mod_auth_ldap.html

[3] https://github.com/jitsi/jicofo/blob/master/README.md#secure-domain
