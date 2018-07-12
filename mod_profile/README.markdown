---
labels:
- 'Stage-Alpha'
summary: 'Replacement for mod\_vcard with vcard4 support and PEP integration'
---

# Introduction

This module provides a replacement for [mod\_vcard]. In addition to
the ageing protocol defined by [XEP-0054], it also supports the [new
vCard 4 based protocol][xep0292] and integrates with [Personal
Eventing Protocol][xep0163].

The vCard 4, [User Avatar][xep0084] and [User Nickname][xep0172]
PEP nodes are updated when the vCard is changed..

# Configuration

    modules_enabled = {
        -- "pep";   -- These two modules must be removed
        -- "vcard";

        "profile";
    }

# Compatibility

Requires Prosody **trunk** as of 2014-05-29. Won't work in 0.10.x.

It depends on the new [mod\_pep\_plus][doc:modules:mod_pep_plus] for PEP support.
