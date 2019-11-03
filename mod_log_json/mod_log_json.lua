local pack = require "util.table".pack;
local json = require "util.json";
local array = require "util.array";
local datetime = require "util.datetime".datetime;

module:set_global();

local function sink_maker(config)
	local logfile = io.open(config.filename, "a+");
	logfile:setvbuf("no");
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
		logfile:write(json.encode(payload), "\n");
	end
end

require"core.loggingmanager".register_sink_type("json", sink_maker);
