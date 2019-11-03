TLS 1.0 and TLS 1.1 are about to be obsolete. This module warns clients
if they are using those versions, to prepare for disabling them.

# Configuration

``` {.lua}
modules_enabled = {
    -- other modules etc
    "warn_legacy_tls";
}

-- This is the default, you can leave it out if you don't wish to
-- customise or translate the message sent.
-- '%s' will be replaced with the TLS version in use.
legacy_tls_warning = [[
Your connection is encrypted using the %s protocol, which has been demonstrated to be insecure and will be disabled soon.  Please upgrade your client.
]]
```

## Options

`legacy_tls_warning`
:   A string. The text of the message sent to clients that use outdated
    TLS versions. Default as in the above example.

`legacy_tls_versions`
:   Set of TLS versions, defaults to
    `{ "SSLv3", "TLSv1", "TLSv1.1" }`{.lua}, i.e. TLS \< 1.2.
