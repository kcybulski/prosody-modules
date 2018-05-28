-- Copyright (C) 2016-2017 Thilo Molitor
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local add_filter = require "util.filters".add_filter;
local remove_filter = require "util.filters".remove_filter;
local datetime = require "util.datetime";

local xmlns_delay = "urn:xmpp:delay";

-- Raise an error if the modules has been loaded as a component in prosody's config
if module:get_host_type() == "component" then
	error(module.name.." should NOT be loaded as a component, check out http://prosody.im/doc/components", 0);
end

local add_delay = function(stanza, session)
	if stanza and stanza.name == "message" and stanza:get_child("delay", xmlns_delay) == nil then
		-- only add delay tag to chat or groupchat messages (should we add a delay to anything else, too???)
		if stanza.attr.type == "chat" or stanza.attr.type == "groupchat" then
			-- session.log("debug", "adding delay to message %s", tostring(stanza));
			stanza = stanza:tag("delay", { xmlns = xmlns_delay, from = session.host, stamp = datetime.datetime()});
		end
	end
	return stanza;
end

module:hook("resource-bind", function(event)
	add_filter(event.session, "stanzas/in", add_delay, 1);
end);
module:hook("smacks-hibernation-end", function(event)
	-- older smacks module versions send only the "intermediate" session in event.session and no session.resumed one
	if event.resumed then
		add_filter(event.resumed, "stanzas/in", add_delay, 1);
	end
end);
module:hook("pre-resource-unbind", function (event)
	remove_filter(event.session, "stanzas/in", add_delay);
end);
