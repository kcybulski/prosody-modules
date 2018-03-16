-- mod_conversejs
-- Copyright (C) 2017 Kim Alvefur

local json_encode = require"util.json".encode;

module:depends"bosh";

local has_ws = pcall(function ()
	module:depends("websocket");
end);

local template = [[
<!DOCTYPE html>
<meta charset="utf-8">
<link rel="stylesheet" type="text/css" media="screen" href="https://cdn.conversejs.org/css/%s.min.css">
<script src="https://cdn.conversejs.org/dist/converse.min.js"></script>
<body><script>converse.initialize(%s);</script>
]]

local more_options = module:get_option("conversejs_options");

module:provides("http", {
	route = {
		GET = function (event)
			local converse_options = {
				bosh_service_url = module:http_url("bosh","/http-bind");
				websocket_url = has_ws and module:http_url("websocket","xmpp-websocket"):gsub("^http", "ws") or nil;
				authentication = module:get_option_string("authentication") == "anonymous" and "anonymous" or "login";
				jid = module.host;
				default_domain = module.host;
			};

			local view_mode_css = "converse";
			if type(more_options) == "table" then
				for k,v in pairs(more_options) do
					converse_options[k] = v;
				end
				if more_options.view_mode == "fullscreen" then
					view_mode_css = "inverse";
				end
			end

			event.response.headers.content_type = "text/html";
			return template:format(view_mode_css, json_encode(converse_options));
		end;
	}
});

