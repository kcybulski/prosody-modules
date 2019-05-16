-- mod_conversejs
-- Copyright (C) 2017 Kim Alvefur

local json_encode = require"util.json".encode;
local xml_escape = require "util.stanza".xml_escape;
local render = require "util.interpolation".new("%b{}", xml_escape, { json = json_encode });

module:depends"http";

local has_bosh = pcall(function ()
	module:depends"bosh";
end);

local has_ws = pcall(function ()
	module:depends("websocket");
end);

pcall(function ()
	module:depends("bookmarks");
end);

local cdn_url = module:get_option_string("conversejs_cdn", "https://cdn.conversejs.org");

local version = module:get_option_string("conversejs_version", "");
if version ~= "" then version = "/" .. version end
local js_url = module:get_option_string("conversejs_script", cdn_url..version.."/dist/converse.min.js");
local css_url = module:get_option_string("conversejs_css", cdn_url..version.."/css/converse.min.css");

local html_template;

do
	local template_filename = module:get_option_string(module.name .. "_html_template", "template.html");
	local template_file, err = module:load_resource(template_filename);
	if template_file then
		html_template, err = template_file:read("*a");
		template_file:close();
	end
	if not html_template then
		module:log("error", "Error loading HTML template: %s", err);
		html_template = render("<h1>mod_{module} could not read the template</h1>\
		<p>Tried to open <b>{filename}</b></p>\
		<pre>{error}</pre>",
			{ module = module.name, filename = template_filename, error = err });
	end
end

local js_template;
do
	local template_filename = module:get_option_string(module.name .. "_js_template", "template.js");
	local template_file, err = module:load_resource(template_filename);
	if template_file then
		js_template, err = template_file:read("*a");
		template_file:close();
	end
	if not js_template then
		module:log("error", "Error loading JS template: %s", err);
		js_template = render("console.log(\"mod_{module} could not read the JS template: %s\", {error|json})",
			{ module = module.name, filename = template_filename, error = err });
	end
end

local user_options = module:get_option("conversejs_options");

local function get_converse_options()
	local allow_registration = module:get_option_boolean("allow_registration", false);
	local converse_options = {
		bosh_service_url = has_bosh and module:http_url("bosh","/http-bind") or nil;
		websocket_url = has_ws and module:http_url("websocket","xmpp-websocket"):gsub("^http", "ws") or nil;
		authentication = module:get_option_string("authentication") == "anonymous" and "anonymous" or "login";
		jid = module.host;
		default_domain = module.host;
		domain_placeholder = module.host;
		allow_registration = allow_registration;
		registration_domain = allow_registration and module.host or nil;
	};

	if type(user_options) == "table" then
		for k,v in pairs(user_options) do
			converse_options[k] = v;
		end
	end

	return converse_options;
end

local add_tags = module:get_option_array("conversejs_tags", {});

module:provides("http", {
	title = "Converse.js";
	route = {
		GET = function (event)
			local converse_options = get_converse_options();

			event.response.headers.content_type = "text/html";
			return render(html_template, {
					header_scripts = { js_url };
					header_style = { css_url };
					header_tags = add_tags;
					conversejs = {
						options = converse_options;
						startup = { script = js_template:format(json_encode(converse_options)); }
					};
				});
		end;

		["GET /prosody-converse.js"] = function (event)
			local converse_options = get_converse_options();

			event.response.headers.content_type = "application/javascript";
			return js_template:format(json_encode(converse_options));
		end;
	}
});

