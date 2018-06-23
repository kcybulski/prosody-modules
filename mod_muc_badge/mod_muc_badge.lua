-- MIT License
--
-- Copyright (c) 2018 Kim Alvefur
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module:depends"http";

local jid_prep = require "util.jid".prep;

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local get_room_from_jid = rawget(mod_muc, "get_room_from_jid") or
	function (jid)
		return rooms[jid];
	end

-- I believe the origins of this template to be in the public domain as per
-- https://github.com/badges/shields/blob/master/LICENSE.md
local template = module:get_option_string("badge_template", [[
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="144" height="20">
<linearGradient id="b" x2="0" y2="100%">
	<stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
	<stop offset="1" stop-opacity=".1"/>
</linearGradient>
<clipPath id="a">
	<rect width="144" height="20" rx="3" fill="#fff"/>
</clipPath>
<g clip-path="url(#a)">
	<path fill="#555" d="M0 0h69v20H0z"/>
	<path fill="#fe7d37" d="M69 0h75v20H69z"/>
	<path fill="url(#b)" d="M0 0h144v20H0z"/>
</g>
<g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110">
	<text x="355" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="590">{label}</text>
	<text x="355" y="140" transform="scale(.1)" textLength="590">{label}</text>
	<text x="1055" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="650">{number}</text>
	<text x="1055" y="140" transform="scale(.1)" textLength="650">{number}</text>
</g>
</svg>
]]);
template = assert(require "util.template"(template));

local label = module:get_option_string("badge_label", "Chatroom");
local number = module:get_option_string("badge_count", "%d online");

module:provides("http", {
	route = {
		["GET /*"] = function (event, path)
			local jid = jid_prep(path);
			if not jid then return end

			local room = get_room_from_jid(jid);
			if not room then return end
			if (room.get_hidden or room.is_hidden)(room) then return end

			local count = 0;
			for _ in pairs(room._occupants) do
				count = count + 1;
			end

			local response = event.response;
			response.headers.content_type = "image/svg+xml";
			local svg = [[<?xml version="1.0"?>]] ..
				tostring(template.apply({
					label = label;
					number = string.format(number, count);
				}));
			return svg;
		end;
	}
});
