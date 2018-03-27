# mod_auth_token

This module enables Prosody to authenticate time-based one-time-pin (TOTP) HMAC tokens.

This is an alternative to "external authentication" which avoids the need to
make a blocking HTTP call to the external authentication service (usually a web application backend).

Instead, the application generates the HMAC token, which is then sent to
Prosody via the XMPP client and Prosody verifies the authenticity of this
token.

If the token is verified, then the user is authenticated.

## How to generate the token

You'll need a shared OTP_SEED value for generating time-based one-time-pin
values and a shared private key for signing the HMAC token.

You can generate the OTP_SEED value with Python, like so:

    >>> import pyotp
    >>> pyotp.random_base32()
    u'XVGR73KMZH2M4XMY'

and the shared secret key as follows:

    >>> import pyotp
    >>> pyotp.random_base32(length=32)
    u'JYXEX4IQOEYFYQ2S3MC5P4ZT4SDHYEA7'

These values then need to go into your Prosody.cfg file:

token_secret = "JYXEX4IQOEYFYQ2S3MC5P4ZT4SDHYEA7"
otp_seed = "XVGR73KMZH2M4XMY"

The application that generates the tokens also needs access to these values.

For an example on how to generate a token, take a look at the `generate_token`
function in the `test_token_auth.lua` file inside this directory.

## Custom SASL auth

This module depends on a custom SASL auth mechanism called X-TOKEN and which
is provided by the file `mod_sasl_token.lua`.

Prosody doesn't automatically pick up this file, so you'll need to update your
configuration file's `plugin_paths` to link to this subdirectory (for example
to `/usr/lib/prosody-modules/mod_auth_token/`).
