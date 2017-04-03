-- mod_http_upload
--
-- Copyright (C) 2015 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- Implementation of HTTP Upload file transfer mechanism used by Conversations
--

-- imports
local st = require"util.stanza";
local lfs = require"lfs";
local url = require "socket.url";
local dataform = require "util.dataforms".new;
local datamanager = require "util.datamanager";
local t_concat = table.concat;
local t_insert = table.insert;
local s_upper = string.upper;
local have_id, id = pcall(require, "util.id"); -- Only available in 0.10+
local uuid = require"util.uuid".generate;
if have_id then
	uuid = id.medium;
end

local function join_path(...) -- COMPAT util.path was added in 0.10
	return table.concat({ ... }, package.config:sub(1,1));
end

-- config
local file_size_limit = module:get_option_number(module.name .. "_file_size_limit", 1024 * 1024); -- 1 MB

--- sanity
local parser_body_limit = module:context("*"):get_option_number("http_max_content_size", 10*1024*1024);
if file_size_limit > parser_body_limit then
	module:log("warn", "%s_file_size_limit exceeds HTTP parser limit on body size, capping file size to %d B",
		module.name, parser_body_limit);
	file_size_limit = parser_body_limit;
end

-- depends
module:depends("http");
module:depends("disco");

-- namespaces
local namespace = "urn:xmpp:http:upload:0";
local legacy_namespace = "urn:xmpp:http:upload";

-- identity and feature advertising
module:add_identity("store", "file", module:get_option_string("name", "HTTP File Upload"));
module:add_feature(namespace);
module:add_feature(legacy_namespace);

module:add_extension(dataform {
	{ name = "FORM_TYPE", type = "hidden", value = namespace },
	{ name = "max-file-size", type = "text-single" },
}:form({ ["max-file-size"] = tostring(file_size_limit) }, "result"));

module:add_extension(dataform {
	{ name = "FORM_TYPE", type = "hidden", value = legacy_namespace },
	{ name = "max-file-size", type = "text-single" },
}:form({ ["max-file-size"] = tostring(file_size_limit) }, "result"));

-- state
local pending_slots = module:shared("upload_slots");

local storage_path = module:get_option_string(module.name .. "_path", join_path(prosody.paths.data, module.name));
lfs.mkdir(storage_path);

local function handle_request(origin, stanza, xmlns, filename, filesize)
	-- local clients only
	if origin.type ~= "c2s" then
		module:log("debug", "Request for upload slot from a %s", origin.type);
		origin.send(st.error_reply(stanza, "cancel", "not-authorized"));
		return true;
	end
	-- validate
	if not filename or filename:find("/") then
		module:log("debug", "Filename %q not allowed", filename or "");
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid filename"));
		return true;
	end
	if not filesize then
		module:log("debug", "Missing file size");
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing or invalid file size"));
		return true;
	elseif filesize > file_size_limit then
		module:log("debug", "File too large (%d > %d)", filesize, file_size_limit);
		origin.send(st.error_reply(stanza, "modify", "not-acceptable", "File too large")
			:tag("file-too-large", {xmlns=xmlns})
				:tag("max-file-size"):text(tostring(file_size_limit)));
		return true;
	end
	local reply = st.reply(stanza);
	reply:tag("slot", { xmlns = xmlns });

	local random_dir;
	repeat random_dir = uuid();
	until lfs.mkdir(join_path(storage_path, random_dir))
		or not lfs.attributes(join_path(storage_path, random_dir, filename))

	datamanager.list_append(origin.username, origin.host, module.name, {
		filename = join_path(storage_path, random_dir, filename), size = filesize, time = os.time() });
	local slot = random_dir.."/"..filename;
	pending_slots[slot] = origin.full_jid;
	local base_url = module:http_url();
	local slot_url = url.parse(base_url);
	slot_url.path = url.parse_path(slot_url.path or "/");
	t_insert(slot_url.path, random_dir);
	t_insert(slot_url.path, filename);
	slot_url.path.is_directory = false;
	slot_url.path = url.build_path(slot_url.path);
	slot_url = url.build(slot_url);
	reply:tag("get"):text(slot_url):up();
	reply:tag("put"):text(slot_url):up();
	origin.send(reply);
	origin.log("debug", "Given upload slot %q", slot);
	return true;
end

-- hooks
module:hook("iq/host/"..namespace..":request", function (event)
	local stanza, origin = event.stanza, event.origin;
	local request = stanza.tags[1];
	local filename = request.attr.filename;
	local filesize = tonumber(request.attr.size);
	return handle_request(origin, stanza, namespace, filename, filesize);
end);

module:hook("iq/host/"..legacy_namespace..":request", function (event)
	local stanza, origin = event.stanza, event.origin;
	local request = stanza.tags[1];
	local filename = request:get_child_text("filename");
	local filesize = tonumber(request:get_child_text("size"));
	return handle_request(origin, stanza, legacy_namespace, filename, filesize);
end);

-- http service
local function upload_data(event, path)
	local uploader = pending_slots[path];
	if not uploader then
		module:log("warn", "Attempt to upload to unknown slot %q", path);
		return; -- 404
	end
	local random_dir, filename = path:match("^([^/]+)/([^/]+)$");
	if not random_dir then
		module:log("warn", "Invalid file path %q", path);
		return 400;
	end
	if #event.request.body > file_size_limit then
		module:log("warn", "Uploaded file too large %d bytes", #event.request.body);
		return 400;
	end
	pending_slots[path] = nil;
	local full_filename = join_path(storage_path, random_dir, filename);
	if lfs.attributes(full_filename) then
		module:log("warn", "File %s exists already, not replacing it", full_filename);
		return 409;
	end
	local fh, ferr = io.open(full_filename, "w");
	if not fh then
		module:log("error", "Could not open file %s for upload: %s", full_filename, ferr);
		return 500;
	end
	local ok, err = fh:write(event.request.body);
	if not ok then
		module:log("error", "Could not write to file %s for upload: %s", full_filename, err);
		os.remove(full_filename);
		return 500;
	end
	ok, err = fh:close();
	if not ok then
		module:log("error", "Could not write to file %s for upload: %s", full_filename, err);
		os.remove(full_filename);
		return 500;
	end
	module:log("info", "File uploaded by %s to slot %s", uploader, random_dir);
	return 201;
end

-- FIXME Duplicated from net.http.server

local codes = require "net.http.codes";
local headerfix = setmetatable({}, {
	__index = function(t, k)
		local v = "\r\n"..k:gsub("_", "-"):gsub("%f[%w].", s_upper)..": ";
		t[k] = v;
		return v;
	end
});

local function send_response_sans_body(response, body)
	if response.finished then return; end
	response.finished = true;
	response.conn._http_open_response = nil;

	local status_line = "HTTP/"..response.request.httpversion.." "..(response.status or codes[response.status_code]);
	local headers = response.headers;
	body = body or response.body or "";
	headers.content_length = #body;

	local output = { status_line };
	for k,v in pairs(headers) do
		t_insert(output, headerfix[k]..v);
	end
	t_insert(output, "\r\n\r\n");
	-- Here we *don't* add the body to the output

	response.conn:write(t_concat(output));
	if response.on_destroy then
		response:on_destroy();
		response.on_destroy = nil;
	end
	if response.persistent then
		response:finish_cb();
	else
		response.conn:close();
	end
end

local serve_uploaded_files = module:depends("http_files").serve(storage_path);

local function serve_head(event, path)
	event.response.send = send_response_sans_body;
	return serve_uploaded_files(event, path);
end

local function serve_hello(event)
	event.response.headers.content_type = "text/html;charset=utf-8"
	return "<!DOCTYPE html>\n<h1>Hello from mod_"..module.name.."!</h1>\n";
end

module:provides("http", {
	route = {
		["GET"] = serve_hello;
		["GET /"] = serve_hello;
		["GET /*"] = serve_uploaded_files;
		["HEAD /*"] = serve_head;
		["PUT /*"] = upload_data;
	};
});

module:log("info", "URL: <%s>; Storage path: %s", module:http_url(), storage_path);
