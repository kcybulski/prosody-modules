-- mod_conversejs
-- Copyright (C) 2017 Kim Alvefur

local json_encode = require"util.json".encode;

module:depends"bosh";

local has_ws = pcall(function ()
	module:depends("websocket");
end);

local template = [[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<link rel="stylesheet" type="text/css" media="screen" href="https://cdn.conversejs.org/css/converse.min.css"/>
<script charset="utf-8" src="https://cdn.conversejs.org/dist/converse.min.js"/>
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
<script>converse.initialize(%s);</script>
</body>
</html>
]]

local more_options = module:get_option("conversejs_options");

module:provides("http", {
	route = {
		GET = function (event)
			local allow_registration = module:get_option_boolean("allow_registration", false);
			local converse_options = {
				bosh_service_url = module:http_url("bosh","/http-bind");
				websocket_url = has_ws and module:http_url("websocket","xmpp-websocket"):gsub("^http", "ws") or nil;
				authentication = module:get_option_string("authentication") == "anonymous" and "anonymous" or "login";
				jid = module.host;
				default_domain = module.host;
				domain_placeholder = module.host;
				allow_registration = allow_registration;
				registration_domain = allow_registration and module.host or nil;
			};

			event.response.headers.content_type = "text/html";
			return template:format(json_encode(converse_options));
		end;
	}
});

