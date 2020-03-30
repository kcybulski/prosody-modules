---
description: HTTP File Upload
labels: 'Stage-Alpha'
---

Introduction
============

This module implements [XEP-0363], versions 0.2 and 0.3, which let
clients upload files over HTTP.

Configuration
=============

mod\_http\_upload relies on Prosodys HTTP server and mod\_http for
serving HTTP requests. See [Prosodys HTTP server documentation][doc:http]
for information about how to configure ports, HTTP Host names etc.

The module can be added as a new Component definition:

``` {.lua}
Component "upload.example.org" "http_upload"
```

It should **not** be added to modules_enabled.

## Discoverability

Prosody makes subdomains of your VirtualHosts easily discoverable by
clients. To make the component discoverable by other hosts, use
[`disco_items`][doc:modules:mod_disco#configuration].

``` {.lua}
VirtualHost "foo.example.org"
disco_items = {
    { "upload.example.com" },
}
```

Limits
------

### Max size

A maximum file size can be set by:

``` {.lua}
http_upload_file_size_limit = 123 -- bytes
```

Default is 1MB (1024\*1024).

This can not be set over the value of `http_max_content_size` (default 10M).
Consider [mod_http_upload_external] instead of attempting to increase
this limit.

### Max age

Files can be set to be deleted after some time:

``` lua
http_upload_expire_after = 60 * 60 * 24 * 7 -- a week in seconds
```

Expired files are deleted when a new upload slot is requested,

A command exists to invoke expiry:

```
prosodyctl mod_http_upload expire [optional list of users]
```

### User quota

A total maximum size of all uploaded files per user can be set by:

``` lua
http_upload_quota = 1234 -- bytes
```

A request for a slot that would take an user over quota is denied.

Path
----

By default, uploaded files are put in a sub-directory of the default
Prosody storage path (usually `/var/lib/prosody`). This can be changed:

``` {.lua}
http_upload_path = "/path/to/uploded/files"
```

Compatibility
=============

Works with Prosody 0.9.x and later.
