-- Log common stats to statsd
--
-- Copyright (C) 2014 Daurnimator
--
-- This module is MIT/X11 licensed.

module:set_global();
module:depends "http";

local s_format = string.format;
local t_insert = table.insert;
local socket = require "socket";
local mt = require "util.multitable";

local meta = mt.new(); meta.data = module:shared"meta";
local data = mt.new(); data.data = module:shared"data";

local function escape(text)
	return text:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n");
end

local function escape_name(name)
	return name:gsub("[^A-Za-z0-9_]", "_"):gsub("^[^A-Za-z_]", "_%1");
end

local function get_timestamp()
	-- Using LuaSocket for that because os.time() only has second precision.
	return math.floor(socket.gettime() * 1000);
end

local function repr_help(metric, docstring)
	docstring = docstring:gsub("\\", "\\\\"):gsub("\n", "\\n");
	return "# HELP "..escape_name(metric).." "..docstring.."\n";
end

-- local allowed_types = { counter = true, gauge = true, histogram = true, summary = true, untyped = true };
-- local allowed_types = { "counter", "gauge", "histogram", "summary", "untyped" };
local function repr_type(metric, type_)
	-- if not allowed_types:contains(type_) then
	-- 	return;
	-- end
	return "# TYPE "..escape_name(metric).." "..type_.."\n";
end

local function repr_label(key, value)
	return key.."=\""..escape(value).."\"";
end

local function repr_labels(labels)
	local values = {}
	for key, value in pairs(labels) do
		t_insert(values, repr_label(escape_name(key), escape(value)));
	end
	if #values == 0 then
		return "";
	end
	return "{"..table.concat(values, ", ").."}";
end

local function repr_sample(metric, labels, value, timestamp)
	return escape_name(metric)..repr_labels(labels).." "..value.." "..timestamp.."\n";
end

module:hook("stats-updated", function (event)
	local all_stats, this = event.stats_extra;
	local host, sect, name, typ, key;
	for stat, value in pairs(event.changed_stats) do
		this = all_stats[stat];
		-- module:log("debug", "changed_stats[%q] = %s", stat, tostring(value));
		host, sect, name, typ = stat:match("^/([^/]+)/([^/]+)/(.+):(%a+)$");
		if host == nil then
			sect, name, typ, host = stat:match("^([^.]+)%.([^:]+):(%a+)$");
		elseif host == "*" then
			host = nil;
		end
		if sect:find("^mod_measure_.") then
			sect = sect:sub(13);
		elseif sect:find("^mod_statistics_.") then
			sect = sect:sub(16);
		end
		key = escape_name(s_format("%s_%s_%s", host or "global", sect, typ));

		if not meta:get(key) then
			if host then
				meta:set(key, "", "graph_title", s_format("%s %s on %s", sect, typ, host));
			else
				meta:set(key, "", "graph_title", s_format("Global %s %s", sect, typ, host));
			end
			meta:set(key, "", "graph_vlabel", this and this.units or typ);
			meta:set(key, "", "graph_category", sect);

			meta:set(key, name, "label", name);
		elseif not meta:get(key, name, "label") then
			meta:set(key, name, "label", name);
		end

		data:set(key, name, value);
	end
end);

local function get_metrics(event)
	local response = event.response;
	response.headers.content_type = "text/plain; version=0.4.4";

	local response = {};
	local timestamp = tostring(get_timestamp());
	for section, data in pairs(data.data) do
		for key, value in pairs(data) do
			local name = "prosody_"..section.."_"..key;
			t_insert(response, repr_help(name, "TODO: add a description here."));
			t_insert(response, repr_type(name, "gauge"));
			t_insert(response, repr_sample(name, {}, value, timestamp));
		end
	end
	return table.concat(response, "");
end

function module.add_host(module)
	module:provides("http", {
		default_path = "metrics";
		route = {
			GET = get_metrics;
		};
	});
end
