local mt = require"util.multitable";
local datetime = require"util.datetime";
local jid_split = require"util.jid".split;
local nodeprep = require"util.encodings".stringprep.nodeprep;
local it = require"util.iterators";
local url = require"socket.url";
local os_time, os_date = os.time, os.date;
local httplib = require "util.http";
local render = require"util.interpolation".new("%b{}", require"util.stanza".xml_escape);

local archive = module:open_store("muc_log", "archive");

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local each_room = rawget(mod_muc, "each_room") or function() return it.values(rooms); end;
local new_muc = not rooms;
if new_muc then
	rooms = module:shared"muc/rooms";
end
local get_room_from_jid = rawget(mod_muc, "get_room_from_jid") or
	function (jid)
		return rooms[jid];
	end

local function get_room(name)
	local jid = name .. '@' .. module.host;
	return get_room_from_jid(jid);
end

local use_oob = module:get_option_boolean(module.name .. "_show_images", false);
module:depends"http";

local template;
do
	local template_filename = module:get_option_string(module.name .. "_template", module.name .. ".html");
	local template_file, err = module:load_resource(template_filename);
	if template_file then
		template, err = template_file:read("*a");
		template_file:close();
	end
	if not template then
		module:log("error", "Error loading template: %s", err);
		template = render("<h1>mod_{module} could not read the template</h1>\
		<p>Tried to open <b>{filename}</b></p>\
		<pre>{error}</pre>",
			{ module = module.name, filename = template_filename, error = err });
	end
end

-- local base_url = module:http_url() .. '/'; -- TODO: Generate links in a smart way
local get_link do
	local link, path = { path = '/' }, { "", "", is_directory = true };
	function get_link(room, date)
		path[1], path[2] = room, date;
		path.is_directory = not date;
		link.path = url.build_path(path);
		return url.build(link);
	end
end

-- Whether room can be joined by anyone
local function open_room(room) -- : boolean
	if type(room) == "string" then
		room = get_room(room);
		-- assumed to be a room object otherwise
	end
	if not room then
		return nil;
	end

	if (room.get_members_only or room.is_members_only)(room) then
		return false;
	end

	if room:get_password() then
		return false;
	end

	return true;
end

module:hook("muc-disco#info", function (event)
	local room = event.room;
	if open_room(room) then
		table.insert(event.form, { name = "muc#roominfo_logs", type="text-single" });
		event.formdata["muc#roominfo_logs"] = module:http_url() .. "/" .. get_link(jid_split(event.room.jid), nil);
	end
end);

local function sort_Y(a,b) return a.year > b.year end
local function sort_m(a,b) return a.n > b.n end

-- Time zone hack?
local t_diff = os_time(os_date("*t")) - os_time(os_date("!*t"));
local function time(t)
	return os_time(t) + t_diff;
end
local function date_floor(t)
	return t - t % 86400;
end

-- Fetch one item
local function find_once(room, query, retval)
	if query then query.limit = 1; else query = { limit = 1 }; end
	local iter, err = archive:find(room, query);
	if not iter then return iter, err; end
	if retval then
		return select(retval, iter());
	end
	return iter();
end

local lazy = module:get_option_boolean(module.name .. "_lazy_calendar", true);

local function hide_presence(request)
	if request.url.query then
		local data = httplib.formdecode(request.url.query);
		if data then
			return data.p == "h"
		end
	end
	return false;
end

-- Produce the calendar view
local function years_page(event, path)
	local request, response = event.request, event.response;

	local room = nodeprep(path:match("^(.*)/$"));
	local is_open = open_room(room);
	if is_open == nil then
		return -- implicit 404
	elseif is_open == false then
		return 403;
	end

	-- Collect each date that has messages
	-- convert it to a year / month / day tree
	local date_list = archive.dates and archive:dates(room);
	local dates = mt.new();
	if date_list then
		for _, date in ipairs(date_list) do
			local when = datetime.parse(date.."T00:00:00Z");
			local t = os_date("!*t", when);
			dates:set(t.year, t.month, t.day, when);
		end
	elseif lazy then
		-- Lazy with many false positives
		local first_day = find_once(room, nil, 3);
		local last_day = find_once(room, { reverse = true }, 3);
		if first_day and last_day then
			first_day = date_floor(first_day);
			last_day = date_floor(last_day);
			for when = first_day, last_day, 86400 do
				local t = os_date("!*t", when);
				dates:set(t.year, t.month, t.day, when);
			end
		else
			return; -- 404
		end
	else
		-- Collect date the hard way
		module:log("debug", "Find all dates with messages");
		local next_day;
		repeat
			local when = find_once(room, { start = next_day; }, 3);
			if not when then break; end
			local t = os_date("!*t", when);
			dates:set(t.year, t.month, t.day, when );
			next_day = date_floor(when) + 86400;
		until not next_day;
	end

	local years = {};

	-- Wrangle Y/m/d tree into year / month / week / day tree for calendar view
	for current_year, months_t in pairs(dates.data) do
		local t = { year = current_year, month = 1, day = 1 };
		local months = { };
		local year = { year = current_year, months = months };
		years[#years+1] = year;
		for current_month, days_t in pairs(months_t) do
			t.day = 1;
			t.month = current_month;
			local tmp = os_date("!*t", time(t));
			local days = {};
			local week = { days = days }
			local weeks = { week };
			local month = { year = year.year, month = os_date("!%B", time(t)), n = current_month, weeks = weeks };
			months[#months+1] = month;
			local current_day = 1;
			for _=1, (tmp.wday+5)%7 do
				days[current_day], current_day = {}, current_day+1;
			end
			for i = 1, 31 do
				t.day = i;
				tmp = os_date("!*t", time(t));
				if tmp.month ~= current_month then break end
				if i > 1 and tmp.wday == 2 then
					days = {};
					weeks[#weeks+1] = { days = days };
					current_day = 1;
				end
				days[current_day] = {
					wday = tmp.wday, day = i, href = days_t[i] and datetime.date(days_t[i])
				};
				current_day = current_day+1;
			end
		end
		table.sort(year, sort_m);
	end
	table.sort(years, sort_Y);

	-- Phew, all wrangled, all that's left is rendering it with the template

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = get_room(room):get_name();
		jid = get_room(room).jid;
		hide_presence = hide_presence(request);
		years = years;
		links = {
			{ href = "../", rel = "up", text = "Room list" },
		};
	});
end

-- Produce the chat log view
local function logs_page(event, path)
	local request, response = event.request, event.response;

	local room, date = path:match("^([^/]+)/([^/]*)/?$");
	room = nodeprep(room);
	if not room then
		return 400;
	elseif date == "" then
		return years_page(event, path);
	end
	local is_open = open_room(room);
	if is_open == nil then
		return -- implicit 404
	elseif is_open == false then
		return 403;
	end
	if date == "latest" then
		local last_day = find_once(room, { reverse = true }, 3);
		response.headers.location = datetime.date(last_day);
		return 303;
	end
	local day_start = datetime.parse(date.."T00:00:00Z");
	if not day_start then
		module:log("debug", "Invalid date format: %q", date);
		return 400;
	end

	local logs, i = {}, 1;
	local iter, err = archive:find(room, {
		["start"] = day_start;
		["end"]   = day_start + 86399;
		["with"]  = hide_presence(request) and "message<groupchat" or nil;
	});
	if not iter then
		module:log("warn", "Could not search archive: %s", err or "no error");
		return 500;
	end

	local first, last;
	for key, item, when in iter do
		local body = item:get_child_text("body");
		local subject = item:get_child_text("subject");
		local verb = nil;
		if subject then
			verb, body = "set the topic to", subject;
		elseif body and body:sub(1,4) == "/me " then
			verb, body = body:sub(5), nil;
		elseif item.name == "presence" then
			-- TODO Distinguish between join and presence update
			verb = item.attr.type == "unavailable" and "has left" or "has joined";
		end
		local oob = use_oob and item:get_child("x", "jabber:x:oob");
		if body or verb or oob then
			local line = {
				key = key;
				datetime = datetime.datetime(when);
				time = datetime.time(when);
				verb = verb;
				body = body;
				nick = select(3, jid_split(item.attr.from));
				st_name = item.name;
				st_type = item.attr.type;
			};
			if oob then
				line.oob = {
					url = oob:get_child_text("url");
					desc = oob:get_child_text("desc");
				}
			end
			logs[i], i = line, i + 1;
		end
		first = first or key;
		last = key;
	end
	if i == 1 and not lazy then return end -- No items

	local next_when, prev_when = "", "";
	local date_list = archive.dates and archive:dates(room);
	if date_list then
		for j = 1, #date_list do
			if date_list[j] == date then
				next_when = date_list[j+1] or "";
				prev_when = date_list[j-1] or "";
				break;
			end
		end
	elseif lazy then
		next_when = datetime.date(day_start + 86400);
		prev_when = datetime.date(day_start - 86400);
	elseif first and last then

		module:log("debug", "Find next date with messages");
		next_when = find_once(room, { after = last }, 3);
		if next_when then
			next_when = datetime.date(next_when);
			module:log("debug", "Next message: %s", next_when);
		end

		module:log("debug", "Find prev date with messages");
		prev_when = find_once(room, { before = first, reverse = true }, 3);
		if prev_when then
			prev_when = datetime.date(prev_when);
			module:log("debug", "Previous message: %s", prev_when);
		end
	end

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = ("%s - %s"):format(get_room(room):get_name(), date);
		jid = get_room(room).jid;
		hide_presence = hide_presence(request);
		lines = logs;
		links = {
			{ href = "./", rel = "up", text = "Calendar" },
			{ href = prev_when, rel = "prev", text = prev_when},
			{ href = next_when, rel = "next", text = next_when},
		};
	});
end

local function list_rooms(event)
	local request, response = event.request, event.response;
	local room_list, i = {}, 1;
	for room in each_room() do
		if not (room.get_hidden or room.is_hidden)(room) then
			room_list[i], i = {
				jid = room.jid;
				href = get_link(jid_split(room.jid), nil);
				name = room:get_name();
				description = room:get_description();
			}, i + 1;
		end
	end

	table.sort(room_list, function (a, b)
		return a.jid < b.jid;
	end);

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = module:get_option_string("name", "Prosody Chatrooms");
		jid = module.host;
		hide_presence = hide_presence(request);
		rooms = room_list;
	});
end

module:provides("http", {
	route = {
		["GET /"] = list_rooms;
		["GET /*"] = logs_page;
	};
});

