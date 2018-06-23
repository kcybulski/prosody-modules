---
depends:
- 'mod\_http'
- 'mod\_muc'
provides:
- http
title: 'mod\_muc\_badge'
---

# Introduction

This module generates a badge, similar the one
<https://opkode.com/blog/xmpp-chat-badge/>

# Configuration

  Option             Type     Default
  ------------------ -------- --------------------------
  `badge_label`      string   `"Chatroom"`
  `badge_count`      string   `"%d online"`
  `badge_template`   string   A SVG image (see source)

The template must be valid XML. If it contains `{label}` then this is
replaced by `badge_label`, similarly, `{count}` is substituted by
`badge_count` with `%d` changed to the number of occupants.
