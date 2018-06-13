---
labels:
- 'Type-Auth'
summary: OAuth authentication
...

Introduction
============

This is an authentication module for the SASL OAUTHBEARER mechanism, as provided by `mod_sasl_oauthbearer`.

Configuration
=============

Per VirtualHost, you'll need to supply your OAuth client Id, secret and the URL which
Prosody must call in order to verify the OAuth token it receives from the XMPP client.

For example, for Github:

	oauth_client_id = "13f8e9cc8928b3409822"
	oauth_client_secret = "983161fd3ah608ea7ef35382668aad1927463978"
	oauth_url = "https://api.github.com/applications/{{oauth_client_id}}/tokens/{{password}}";

	authentication = "oauthbearer"
