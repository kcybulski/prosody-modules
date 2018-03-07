---
summary: Answers disco#info queries on the behalf of the recipient
---

Description
===========

This module intercepts disco#info queries and checks if we already know the
capabilities of this session, in which case we don’t transmit the iq and answer
it ourselves.
