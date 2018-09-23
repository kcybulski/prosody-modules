local st = require "util.stanza";
local jid = require "util.jid";
local id = require "util.id";

local pubsub = module:depends "pubsub".service;

local name = module:get_option_string("name", "PubSub Service on "..module.host);
local help = name..[[

Commands:

- `help` - this help message
- `list` - list available nodes
- `subscribe node` - subscribe to a node
- `unsubscribe node` - unsubscribe from a node]];
if pubsub.get_last_item then -- COMPAT not available in 0.10
	help = help ..  "\n- `last node` - send the last item (again)"
end

module:hook("message/host", function (event)
	local origin, stanza = event.origin, event.stanza;
	local body = stanza:get_child_text("body");
	if not body then return end -- bail out

	local from = stanza.attr.from;

	local reply = st.reply(stanza);
	reply.attr.id = id.medium();

	local command, node_arg = body:match("^(%a+)%s+(.*)");
	command = (command or body):lower();

	if command == "help" then
		reply:body(help);
	elseif command == "list" then
		local ok, nodes = pubsub:get_nodes(from);
		if ok then
			local list = {};
			for node, node_obj in pairs(nodes) do
				table.insert(list, ("- `%s` %s"):format(node, node_obj.config.title or ""));
			end
			reply:body(table.concat(list, "\n"));
		else
			reply:body(nodes);
		end
	elseif command == "subscribe" then
		local ok, err = pubsub:add_subscription(node_arg, from, jid.bare(from), { ["pubsub#include_body"] = true });
		reply:body(ok and "OK" or err);
	elseif command == "unsubscribe" then
		local ok, err = pubsub:remove_subscription(node_arg, from, jid.bare(from));
		reply:body(ok and "OK" or err);
	elseif command == "last" and pubsub.get_last_item then
		local ok, item_id, item = pubsub:get_last_item(node_arg, from);
		if not ok then
			reply:body(item_id); -- err message
		elseif not item_id then
			reply:body("node is empty");
		else
			pubsub.config.broadcaster("items", node_arg, {
				[from] = { ["pubsub#include_body"] = true }
			}, item);
			reply:body("OK");
		end
	else
		reply:body("Unknown command. `help` to list commands.");
	end
	origin.send(reply);
	return true;
end);
