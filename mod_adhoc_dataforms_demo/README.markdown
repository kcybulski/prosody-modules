# Introduction

This module adds an [Ad-Hoc command][xep0050] with a demo [data
form][xep0004] that includes all kinds of fields. It's meant to help
debug both Prosodys
[`util.dataforms`][doc:developers:util:dataforms] library and
clients, eg seeing how various field types are rendered.

# Configuration

Simply add it to [`modules_enabled`][doc:modules_enabled] like any
other module.

``` {.lua}
modules_enabled = {
    -- All your other modules etc
    "adhoc_dataforms_demo";
}
```

# Usage

In your Ad-Hoc capable client, look for **Dataforms Demo**, and execute
it. You should see a form with various kinds of fields.
