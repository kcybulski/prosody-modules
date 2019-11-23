local pack = require "util.table".pack;
local json = require "util.json";
local array = require "util.array";
local datetime = require "util.datetime".datetime;
local socket = require "socket";

module:set_global();

local function sink_maker(config)
	local send = function () end
	if config.filename then
		local logfile = io.open(config.filename, "a+");
		logfile:setvbuf("no");
		function send(payload)
			logfile:write(payload, "\n");
		end
	elseif config.udp_host and config.udp_port then
		local conn = socket.udp();
		conn:setpeername(config.udp_host, config.udp_port);
		function send(payload)
			conn:send(payload);
		end
	end
	return function (source, level, message, ...)
		local args = pack(...);
		for i = 1, args.n do
			if args[i] == nil then
				args[i] = json.null;
			elseif type(args[i]) ~= "string" or type(args[i]) ~= "number" then
				args[i] = tostring(args[i]);
			end
		end
		args.n = nil;
		local payload = {
			datetime = datetime(),
			source = source,
			level = level,
			message = message,
			args = array(args);
		};
		send(json.encode(payload));
	end
end

function module.unload()
	-- deregister
	require"core.loggingmanager".register_sink_type("json", nil);
end

require"core.loggingmanager".register_sink_type("json", sink_maker);
