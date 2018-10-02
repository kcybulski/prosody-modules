local adhoc_new = module:require "adhoc".new;
local adhoc_simple_form = require "util.adhoc".new_simple_form;
local new_token = require "util.id".long;
local jid_prepped_split = require "util.jid".prepped_split;
local http_formdecode = require "net.http".formdecode;
local usermanager = require "core.usermanager";
local dataforms_new = require "util.dataforms".new;
local tohtml = require "util.stanza".xml_escape
local tostring = tostring;

local reset_tokens = module:open_store();

local max_token_age = module:get_option_number("password_reset_validity", 86400);

local serve = module:depends"http_files".serve;

module:depends"adhoc";
module:depends"http";

local function apply_template(template, args)
	return
		template:gsub("{{([^}]*)}}", function (k)
			if args[k] then
				return tohtml(args[k])
			else
				return k
			end
		end)
end

function generate_page(event)
	local request, response = event.request, event.response;

	local token = request.url.query;
	local reset_info = token and reset_tokens:get(token);

	response.headers.content_type = "text/html; charset=utf-8";

	if not reset_info or os.difftime(os.time(), reset_info.generated_at) > max_token_age then
		module:log("warn", "Expired token: %s", token or "<none>");
		local template = assert(module:load_resource("password_reset/password_result.html")):read("*a");

		return apply_template(template, { classes = "alert-danger", message = "This link has expired." })
	end

	local template = assert(module:load_resource("password_reset/password_reset.html")):read("*a");

	return apply_template(template, { jid = reset_info.user.."@"..module.host, token = token });
end

function handle_form(event)
	local request, response = event.request, event.response;
	local form_data = http_formdecode(request.body);
	local password, token = form_data["password"], form_data["token"];

	local reset_info = reset_tokens:get(token);

	local template = assert(module:load_resource("password_reset/password_result.html")):read("*a");

	response.headers.content_type = "text/html; charset=utf-8";

	if not reset_info or os.difftime(os.time(), reset_info.generated_at) > max_token_age then
		return apply_template(template, { classes = "alert-danger", message = "This link has expired." })
	end

	local ok, err = usermanager.set_password(reset_info.user, password, module.host);

	if ok then
		reset_tokens:set(token, nil);

		return apply_template(template, { classes = "alert-success",
			message = "Your password has been updated! Happy chatting :)" })
	else
		module:log("debug", "Resetting password failed: " .. tostring(err));

		return apply_template(template, { classes = "alert-danger", message = "An unknown error has occurred." })
	end
end

module:provides("http", {
	route = {
		["GET /bootstrap.min.css"] = serve(module:get_directory() .. "/password_reset/bootstrap.min.css");
		["GET /reset"] = generate_page;
		["POST /reset"] = handle_form;
	};
});

-- Changing a user's password
local reset_password_layout = dataforms_new{
	title = "Generate password reset link";
	instructions = "Please enter the details of the user who needs a reset link.";

	{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/adhoc/mod_password_reset" };
	{ name = "accountjid", type = "jid-single", required = true, label = "JID" };
};

local reset_command_handler = adhoc_simple_form(reset_password_layout, function (data, errors)
	if errors then
		local errmsg = {};
		for name, text in pairs(errors) do
			errmsg[#errmsg + 1] = name .. ": " .. text;
		end
		return { status = "completed", error = { message = table.concat(errmsg, "\n") } };
	end

	local jid = data.accountjid;
	local user, host = jid_prepped_split(jid);

	if host ~= module.host then
		return {
			status = "completed";
			error = { message = "You may only generate password reset links for users on "..module.host.."." };
		};
	end

	local token = new_token();
	reset_tokens:set(token, {
		generated_at = os.time();
		user = user;
	});

	return { info = module:http_url() .. "/reset?" .. token, status = "completed" };
end);

local adhoc_reset = adhoc_new(
	"Generate password reset link",
	"password_reset",
	reset_command_handler,
	"admin"
);

module:add_item("adhoc", adhoc_reset);
