---
labels:
- 'Stage-Experimental'
summary: Prototype MAM summary
---

This is a prototype for an experimental archive summary API recently
added in [Prosody trunk](https://hg.prosody.im/trunk/rev/2c5546cc5c70).

# Protocol

::: {.alert .alert-danger}
This is not a finished protocol, but a prototype meant for testing.
:::

A basic query:

``` {.xml}
<iq id="lx7" type="get">
  <summary xmlns="xmpp:prosody.im/mod_map"/>
</iq>
```

Answered like:

``` {.xml}
<?xml version="1.0"?>
<iq type="result" id="lx7">
  <summary xmlns="xmpp:prosody.im/mod_map">
    <item jid="juliet@capulet.lit">
      <count>3</count>
    </item>
  </summary>
</iq>
```

It can also take dataform and RSM parameters similar to a [filtered MAM
query](https://xmpp.org/extensions/xep-0313.html#filter).

E.g if the last message you received had an id `09af3-cc343-b409f` then
the following query would tell you who sent you messages since:

``` {.xml}
<iq id="lx8" type="get">
  <summary xmlns="xmpp:prosody.im/mod_map">
    <set xmlns="http://jabber.org/protocol/rsm">
      <max>10</max>
      <after>09af3-cc343-b409f</after>
    </set>
  </summary>
</iq>
```
