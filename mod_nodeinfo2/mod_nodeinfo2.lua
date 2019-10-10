local json = require "util.json";
local array = require "util.array";

module:depends("http");

local total_users = 0;
for _ in require "core.usermanager".users(module.host) do -- TODO refresh at some interval?
	total_users = total_users + 1;
end

module:provides("http", {
	default_path = "/.well-known/x-nodeinfo2";
	route = {
		GET = function (event)
			event.response.headers.content_type = "application/json";
			return json.encode({
				version = "1.0";
				server = {
					baseUrl = module:http_url("","/");
					name = module.host;
					software = "Prosody";
					version = prosody.version;
				};
				--[[ TODO re-use data from mod_server_contact_info ?
				organization = {
					name = "";
					contact = "";
					account = "";
				};
				--]]
				protocols = array {
					"xmpp",
				};
				--[[ TODO would be cool to identify local transports
				services = {
					inbound = array {
						"irc";
					};
					outbound = array {
					};
				};
				--]]
				openRegistrations = module:get_option_boolean("allow_registration", false);
				usage = {
					users = {
						total = total_users;
						-- TODO how would one calculate these?
						-- activeHalfyear = 1;
						-- activeMonth = 1;
						-- activeWeek = 1;
					};
					-- localPosts = 0;
					-- localComments = 0;
				};
			});
		end;
	}
});

