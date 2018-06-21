-- Log common stats to statsd
--
-- Copyright (C) 2014 Daurnimator
--
-- This module is MIT/X11 licensed.

module:set_global();
module:depends "http";

local tostring = tostring;
local t_insert = table.insert;
local t_concat = table.concat;
local socket = require "socket";

local data = {};

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
	return "{"..t_concat(values, ", ").."}";
end

local function repr_sample(metric, labels, value, timestamp)
	return escape_name(metric)..repr_labels(labels).." "..value.." "..timestamp.."\n";
end

module:hook("stats-updated", function (event)
	local all_stats, this = event.stats_extra;
	local host, sect, name, typ;
	data = {};
	for stat, value in pairs(event.stats) do
		this = all_stats[stat];
		-- module:log("debug", "changed_stats[%q] = %s", stat, tostring(value));
		host, sect, name, typ = stat:match("^/([^/]+)/([^/]+)/(.+):(%a+)$");
		if host == nil then
			sect, name, typ = stat:match("^([^.]+)%.(.+):(%a+)$");
		elseif host == "*" then
			host = nil;
		end
		if sect:find("^mod_measure_.") then
			sect = sect:sub(13);
		elseif sect:find("^mod_statistics_.") then
			sect = sect:sub(16);
		end

		local key = escape_name("prosody_"..sect.."_"..name);
		local field = {
			value = value,
			labels = {},
			-- TODO: Use the other types where it makes sense.
			typ = (typ == "rate" and "counter" or "gauge"),
		};
		if host then
			field.labels.host = host;
		end
		if data[key] == nil then
			data[key] = {};
		end
		t_insert(data[key], field);
	end
end);

local function get_metrics(event)
	local response = event.response;
	response.headers.content_type = "text/plain; version=0.4.4";

	local answer = {};
	local timestamp = tostring(get_timestamp());
	for key, fields in pairs(data) do
		t_insert(answer, repr_help(key, "TODO: add a description here."));
		t_insert(answer, repr_type(key, fields[1].typ));
		for _, field in pairs(fields) do
			t_insert(answer, repr_sample(key, field.labels, field.value, timestamp));
		end
	end
	return t_concat(answer, "");
end

function module.add_host(module)
	module:provides("http", {
		default_path = "metrics";
		route = {
			GET = get_metrics;
		};
	});
end
