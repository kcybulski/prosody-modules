local json = require "util.json";
local array = require "util.array";
local get_stats = require "core.statsmanager".get_stats;

module:depends("http");
module:depends("measure_message_e2ee");

local total_users = 0;
for _ in require "core.usermanager".users(module.host) do -- TODO refresh at some interval?
	total_users = total_users + 1;
end

module:provides("http", {
	default_path = "/.well-known/x-nodeinfo2";
	route = {
		GET = function (event)
			local stats, changed_only, extras = get_stats();
			local message_count = nil;
			for stat, value in pairs(stats) do
				if stat == "/*/mod_measure_message_e2ee/message:rate" then
					message_count = extras[stat].total;
				end
			end

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
					localPosts = message_count;
					localComments = message_count;
				};
			});
		end;
	}
});

