-- mod_storage_xmlarchive
-- Copyright (C) 2015-2017 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- luacheck: ignore unused self

local lfs = require "lfs";
local dm = require "core.storagemanager".olddm;
local hmac_sha256 = require"util.hashes".hmac_sha256;
local st = require"util.stanza";
local dt = require"util.datetime";
local new_stream = require "util.xmppstream".new;
local empty = {};

if not dm.append_raw then
	module:require"datamanager_append_raw";
end

local archive = {};
local archive_mt = { __index = archive };

local is_stanza = st.is_stanza or function (s)
	return getmetatable(s) == st.stanza_mt;
end

function archive:append(username, _, data, when, with)
	if not is_stanza(data) then
		module:log("error", "Attempt to store non-stanza object, traceback: %s", debug.traceback());
		return nil, "unsupported-datatype";
	end

	username = username or "@";
	data = tostring(data) .. "\n";

	local day = dt.date(when);
	local ok, err = dm.append_raw(username.."@"..day, self.host, self.store, "xml", data);
	if not ok then
		return nil, err;
	end

	-- If the day-file is missing then we need to add it to the list of days
	local first_of_day = not lfs.attributes(dm.getpath(username .. "@" .. day, self.host, self.store, "list"));

	local offset = ok and err or 0;

	local id = day .. "-" .. hmac_sha256(username.."@"..day.."+"..offset, data, true):sub(-16);
	ok, err = dm.list_append(username.."@"..day, self.host, self.store,
		{ id = id, when = dt.datetime(when), with = with, offset = offset, length = #data });
	if ok and first_of_day then
		ok, err = dm.list_append(username, self.host, self.store, day);
	end
	if not ok then
		return nil, err;
	end
	return id;
end

function archive:_get_idx(username, id, dates)
	module:log("debug", "Looking for item with id %q", id);
	dates = dates or self:dates(username) or empty;
	local date = id:match("^%d%d%d%d%-%d%d%-%d%d");
	for d = 1, #dates do
		if not date or date == dates[d] then
			module:log("debug", "Loading index for %s", dates[d]);
			local items = dm.list_load(username .. "@" .. dates[d], self.host, self.store) or empty;
			for i = 1, #items do
				if items[i].id == id then
					module:log("debug", "Found item!");
					return d, i, items;
				end
			end
			if date then
				return; -- Assuming no duplicates
			end
		elseif date and date < dates[d] then
			module:log("debug", "Skipping remaining dates after %s", date);
			return; -- List is assumed to be sorted
		end
	end
	module:log("debug", "Item not found");
end

function archive:find(username, query)
	username = username or "@";
	query = query or empty;

	local result;
	local function cb(_, stanza)
		assert(not result, "Multiple items in chunk");
		result = stanza;
	end

	local stream_session = { notopen = true };
	local stream_callbacks = { handlestanza = cb, stream_ns = "jabber:client", default_ns = "jabber:client" };
	local stream = new_stream(stream_session, stream_callbacks);
	local dates = self:dates(username) or empty;
	local function reset_stream()
		stream:reset();
		stream_session.notopen = true;
		stream:feed(st.stanza("stream", { xmlns = "jabber:client" }):top_tag());
		stream_session.notopen = nil;
	end
	reset_stream();

	local limit = query.limit;
	local start_day, step, last_day = 1, 1, #dates;
	local count = 0;
	local rev = query.reverse;
	if query.start then
		local d = dt.date(query.start);
		for i = 1, #dates do
			if dates[i] == d then
				start_day = i; break;
			end
		end
	end
	if query["end"] then
		local d = dt.date(query["end"]);
		for i = #dates, 1, -1 do
			if dates[i] == d then
				last_day = i; break;
			end
		end
	end
	local items;
	local first_item, last_item;
	if rev then
		start_day, step, last_day = last_day, -step, start_day;
		if query.before then
			local before_day, before_item, items_ = self:_get_idx(username, query.before, dates);
			if before_day and before_day <= start_day then
				if before_item then
					first_item = before_item - 1;
				else
					first_item = #items_;
				end
				last_item = 1;
				start_day = before_day;
				items = items_;
			end
		end
	elseif query.after then
		local after_day, after_item, items_ = self:_get_idx(username, query.after, dates);
		if after_day and after_day >= start_day then
			if after_item then
				first_item = after_item + 1;
			else
				first_item = 1;
			end
			last_item = #items_;
			start_day = after_day;
			items = items_;
		end
	end

	local date_open, xmlfile;
	local function read_xml(date, offset, length)
		if xmlfile and date ~= date_open then
			module:log("debug", "Closing XML file for %s", date_open);
			xmlfile:close();
			xmlfile = nil;
		end
		if not xmlfile then
			date_open = date;
			local filename = dm.getpath(username .. "@" .. date, self.host, self.store, "xml");
			local ferr;
			xmlfile, ferr = io.open(filename);
			if not xmlfile then
				module:log("error", "Error: %s", ferr);
				return nil, ferr;
			end
			module:log("debug", "Opened XML file %s", filename);
		end
		local pos, err = xmlfile:seek("set", offset);
		if pos ~= offset then
			return nil, err or "seek-failed";
		end
		return xmlfile:read(length);
	end

	return function ()
		if limit and count >= limit then if xmlfile then xmlfile:close() end return; end
		for d = start_day, last_day, step do
			local date = dates[d];
			if not items then
				module:log("debug", "Loading index for %s", date);
				start_day = d;
				items = dm.list_load(username .. "@" .. date, self.host, self.store) or empty;
				if not rev then
					first_item, last_item = 1, #items;
				else
					first_item, last_item = #items, 1;
				end
			end

			local q_with, q_start, q_end = query.with, query.start, query["end"];
			for i = first_item, last_item, step do
				local item = items[i];
				if not item then
					module:log("warn", "data[%q][%d] is nil", date, i);
					break;
				end

				local i_when, i_with = item.when, item.with;

				if type(i_when) == "string" then
					i_when = dt.parse(i_when);
				end
				if type(i_when) ~= "number" then
					module:log("warn", "data[%q][%d].when is invalid", date, i);
					break;
				end

				if  (not q_with or i_with == q_with)
				and (not q_start or i_when >= q_start)
				and (not q_end or i_when <= q_end) then
					count = count + 1;
					first_item = i + step;

					local data = read_xml(date, item.offset, item.length);
					if not data then return end
					local ok, err = stream:feed(data);
					if not ok then
						module:log("warn", "Parse error in %s@%s/%s/%q[%d]: %s", username, self.host, self.store, i, err);
						reset_stream();
					end
					if result then
						local stanza = result;
						result = nil;
						return item.id, stanza, i_when, i_with;
					end
				end
			end
			items = nil;
			if xmlfile then
				xmlfile:close();
				xmlfile = nil;
			end
		end
	end
end

function archive:delete(username, query)
	username = username or "@";
	query = query or empty;
	if query.with or query.start or query.after then
		return nil, "not-implemented"; -- Only trimming the oldest messages
	end
	local before = query.before or query["end"] or "9999-12-31";
	if type(before) == "number" then before = dt.date(before); else before = before:sub(1, 10); end
	local dates, err = self:dates(username);
	if not dates or next(dates) == nil then
		if not err then return true end -- already empty
		return dates, err;
	end
	if dates[1] > before then return true; end -- Nothing to delete
	local remaining_dates = {};
	for d = 1, #dates do
		if dates[d] >= before then
			table.insert(remaining_dates, dates[d]);
		end
	end
	table.sort(remaining_dates);
	local ok, err = dm.list_store(username, self.host, self.store, remaining_dates);
	if not ok then return ok, err; end
	for d = 1, #dates do
		if dates[d] < before then
			os.remove(dm.getpath(username .. "@" .. dates[d], self.host, self.store, "list"));
			os.remove(dm.getpath(username .. "@" .. dates[d], self.host, self.store, "xml"));
		end
	end
	return true;
end

function archive:dates(username)
	module:log("debug", "Loading root index for %s", username);
	local dates, err = dm.list_load(username, self.host, self.store);
	if not dates then return dates, err; end
	assert(type(dates[1]) == "string" and type(dates[#dates]) == "string",
		"Archive does not appear to be in xmlarchive format");
	return dates;
end

local provider = {};
function provider:open(store, typ)
	if typ ~= "archive" then return nil, "unsupported-store"; end
	return setmetatable({ host = module.host, store = store }, archive_mt);
end

function provider:purge(username)
	local encoded_username = dm.path_encode((username or "@") .. "@");
	local basepath = prosody.paths.data .. "/" .. dm.path_encode(module.host);
	for store in lfs.dir(basepath) do
		store = basepath .. "/" .. dm.path_encode(store);
		if lfs.attributes(store, "mode") == "directory" then
			for file in lfs.dir(store) do
				if file:sub(1, #encoded_username) == encoded_username then
					if file:sub(-4) == ".xml" or file:sub(-5) == ".list" then
						os.remove(store .. "/" .. file);
					end
				end
			end
			return true;
		end
	end
end

module:provides("storage", provider);


function module.command(arg)
	local jid = require "util.jid";
	if arg[1] == "convert" and (arg[2] == "to" or arg[2] == "from") and arg[4] then
		local convert;
		if arg[2] == "to" then
			local xml = require "util.xml";
			function convert(user, host, store)
				local dates, err = archive.dates({ host = host, store = store }, user);
				if not dates then assert(not err, err); return end
				assert(dm.list_store(user, host, store, nil));
				for _, date in ipairs(dates) do
					print(date);
					local items = assert(dm.list_load(user .. "@" .. date, host, store));
					local xmlfile = assert(io.open(dm.getpath(user .. "@" .. date, host, store, "xml")));
					for _, item in ipairs(items) do
						assert(xmlfile:seek("set", item.offset));
						local data = assert(xmlfile:read(item.length));
						assert(#data == item.length, "short read");
						data = assert(xml.parse(data));
						data = st.preserialize(data);
						data.key = item.id;
						data.with = item.with;
						data.when = tonumber(item.when) or dt.parse(item.when);
						data.attr.stamp = item.when;
						data.attr.stamp_legacy = dt.legacy(data.when);
						assert(dm.list_append(user, host, store, data));
					end
				end
			end
		else -- convert from internal
			function convert(user, host, store)
				local items, err = dm.list_load(user, host, store);
				if not items then assert(not err, err); return end
				local dates = {};
				local dayitems, date, xmlfile;
				for _, item in ipairs(items) do
					local meta = {
						id = item.key;
						with = item.with;
						when = item.when or dt.parse(item.attr.stamp);
					};
					local current_date = dt.date(meta.when);
					if current_date ~= date then
						if xmlfile then
							assert(xmlfile:close());
						end
						if dayitems then
							assert(dm.list_store(user .. "@" .. date, host, store, dayitems));
						end
						print(current_date);
						dayitems = {};
						date = current_date;
						table.insert(dates, date);
						xmlfile = assert(io.open(dm.getpath(user .. "@" .. date, host, store, "xml"), "w"));
					end
					item.attr.stamp, item.attr.stamp_legacy = nil, nil;
					local stanza = tostring(st.deserialize(item)) .. "\n";
					meta.offset, meta.length = xmlfile:seek(), #stanza;
					assert(xmlfile:write(stanza));
					table.insert(dayitems, meta);
				end
				assert(xmlfile:close());
				assert(dm.list_store(user .. "@" .. date, host, store, dayitems));
				assert(dm.list_store(user, host, store, dates));
			end
		end

		local store = arg[4];
		if arg[3] == "internal" then
			for i = 5, #arg do
				local user, host = jid.prepped_split(arg[i]);
				if not user then
					print(string.format("Argument #%d (%q) is an invalid JID, aborting", i, arg[i]));
					os.exit(1);
				end
				convert(user, host, store);
			end
			print("Done");
			return 0;
		else
			print("Currently only conversion to/from mod_storage_internal is supported");
			print("Check out https://modules.prosody.im/mod_migrate");
		end
	end
	print("prosodyctl mod_storage_xmlarchive convert (from|to) internal (archive|archive2|muc_log) user@host");
end

