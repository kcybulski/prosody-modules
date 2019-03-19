-- mod_conversejs
-- Copyright (C) 2017 Kim Alvefur

local json_encode = require"util.json".encode;

module:depends"http";

local has_bosh = pcall(function ()
	module:depends"bosh";
end);

local has_ws = pcall(function ()
	module:depends("websocket");
end);

local cdn_url = module:get_option_string("conversejs_cdn", "https://cdn.conversejs.org");

local version = module:get_option_string("conversejs_version", "");
if version ~= "" then version = "/" .. version end
local js_url = module:get_option_string("conversejs_script", cdn_url..version.."/dist/converse.min.js");
local css_url = module:get_option_string("conversejs_css", cdn_url..version.."/css/converse.min.css");

local html_template = ([[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<link rel="stylesheet" type="text/css" media="screen" href="$css_url"/>
<script charset="utf-8" src="$js_url"></script>
<title>Prosody IM and Converse.js</title>
</head>
<body>
<noscript>
<h1>Converse.js</h1>
<p>I&apos;m sorry, but this XMPP client application won&apos;t work without JavaScript.</p>
<p>Perhaps you would like to try one of these clients:</p>
<dl>
<dt>Desktop</dt>
<dd><ul>
<li><a href="https://gajim.org/">Gajim</a></li>
<li><a href="https://poez.io/">Poezio</a></li>
<li><a href="https://swift.im/">Swift</a></li>
</ul></dd>
<dt>Mobile</dt>
<dd><ul>
<li><a href="https://github.com/siacs/Conversations">Conversations</a></li>
<li><a href="https://yaxim.org/">Yaxim</a></li>
</ul></dd>
</dl>
<p><a href="https://xmpp.org/software/clients.html">More clients...</a></p>
</noscript>
<script>%s</script>
</body>
</html>
]]):gsub("$([%w_]+)", { js_url = js_url, css_url = css_url });

js_template = [[
if(typeof converse == 'undefined') {
	var div = document.createElement("div");
	var noscript = document.getElementsByTagName("noscript")[0];
	div.innerHTML = noscript.innerText;
	document.body.appendChild(div);
} else {
	converse.initialize(%s);
}
]];

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

local add_tags = module:get_option_set("conversejs_tags");

if add_tags then
	local tags = {};
	for tag in add_tags do
		table.insert(tags, tag);
	end
	html_template = html_template:gsub("</head>", table.concat(tags, "\n"):gsub("%%", "%%").."\n</head>");
end

module:provides("http", {
	title = "Converse.js";
	route = {
		GET = function (event)
			local converse_options = get_converse_options();

			event.response.headers.content_type = "text/html";
			return html_template:format(js_template:format(json_encode(converse_options)));
		end;

		["GET /prosody-converse.js"] = function (event)
			local converse_options = get_converse_options();

			event.response.headers.content_type = "application/javascript";
			return js_template:format(json_encode(converse_options));
		end;
	}
});

