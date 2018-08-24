# Introduction

This module exposes users [microblogging][xep277] on Prosodys built-in HTTP server.

# Configuration

The module itself has no options. However it uses the access control
mechanisms in PubSub, so users must reconfigure their microblogging node
to allow access, by setting `access_model` to `open`.
E.g. Gajim has UI for this, look for "Personal Events" → "Configure
services".

