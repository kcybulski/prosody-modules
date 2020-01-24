local array = require "util.array";
local jid = require "util.jid";
local json = require "util.json";
local st = require "util.stanza";
local xml = require "util.xml";

local simple_types = {
	-- basic message
	body = "text_tag",
	subject = "text_tag",
	thread = "text_tag",

	-- basic presence
	show = "text_tag",
	status = "text_tag",
	priority = "text_tag",

	state = {"name", "http://jabber.org/protocol/chatstates"},
	nick = {"text_tag", "http://jabber.org/protocol/nick", "nick"},
	delay = {"attr", "urn:xmpp:delay", "delay", "stamp"},
	replace = {"attr", "urn:xmpp:message-correct:0", "replace", "id"},

	-- XEP-0045 MUC
	-- TODO history, password, ???
	join = {"bool_tag", "http://jabber.org/protocol/muc", "x"},

	-- XEP-0071
	-- FIXME xmlns is awkward
	html = {
		"func", "http://jabber.org/protocol/xhtml-im", "html",
		function (s) --> json string
			return tostring(s:get_child("body", "http://www.w3.org/1999/xhtml"));
		end;
		function (s) --> xml
			if type(s) == "string" then
				return xml.parse([[<html xmlns='http://jabber.org/protocol/xhtml-im'>]]..s..[[</html>]]);
			end
		end;
	};

	-- XEP-0199
	ping = {"bool_tag", "urn:xmpp:ping", "ping"},

	-- XEP-0030
	disco = {
		"func", "http://jabber.org/protocol/disco#info", "query",
		function (s) --> array of features
			local identities, features = array(), array();
			for tag in s:childtags() do
				if tag.name == "identity" and tag.attr.category and tag.attr.type then
					identities:push({ category = tag.attr.category, type = tag.attr.type, name = tag.attr.name });
				elseif tag.name == "feature" and tag.attr.var then
					features:push(tag.attr.var);
				end
			end
			return { node = s.attr.node, identities = identities, features = features, };
		end;
		function  (s)
			local disco = st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#info" });
			if type(s) == "table" then
				disco.attr.node = tostring(s.node);
				if s.identities then
					for _, identity in ipairs(s.identities) do
						disco:tag("identity", { category = identity[1], type = identity[2] }):up();
					end
				end
				if s.features then
					for feature in ipairs(s.features) do
						disco:tag("feature", { var = feature }):up();
					end
				end
			end
			return disco;
		end;
	};

	items = {
		"func", "http://jabber.org/protocol/disco#items", "query",
		function (s) --> array of features
			local items = array();
			for item in s:childtags("item") do
				items:push({ jid = item.attr.jid, node = item.attr.node, name = item.attr.name });
			end
			return items;
		end;
		function  (s)
			local disco = st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#items" });
			if type(s) == "table" then
				for _, item in ipairs(s) do
					disco:tag("item", item);
				end
			end
			return disco;
		end;
	};

	oob_url = {"func", "jabber:iq:oob", "query",
		function (s)
			return s:get_child_text("url");
		end;
		function (s)
			if type(s) == "string" then
				return st.stanza("query", { xmlns = "jabber:iq:oob" }):text_tag("url", s);
			end
		end;
	};

	-- XEP-XXXX: User-defined Data Transfer
	payload = {"func", "urn:xmpp:udt:0", "payload",
		function (s)
			local rawjson = s:get_child_text("json", "urn:xmpp:json:0");
			if not rawjson then return nil, "missing-json-payload"; end
			local parsed, err = json.decode(rawjson);
			if not parsed then return nil, err; end
			return {
				datatype = s.attr.datatype;
				data = parsed;
			};
		end;
		function (s)
			if type(s) == "table" then
				return st.stanza("payload", { xmlns = "urn:xmpp:udt:0", datatype = s.datatype })
					:tag("json", { xmlns = "urn:xmpp:json:0" }):text(json.encode(s.data));
			end;
		end
	};

};

local implied_kinds = {
	disco = "iq",
	items = "iq",
	ping = "iq",

	body = "message",
	html = "message",
	replace = "message",
	state = "message",
	subject = "message",
	thread = "message",

	join = "presence",
	priority = "presence",
	show = "presence",
	status = "presence",
}

local kind_by_type = {
	get = "iq", set = "iq", result = "iq",
	normal = "message", chat = "message", headline = "message", groupchat = "message",
	available = "presence", unavailable = "presence",
	subscribe = "presence", unsubscribe = "presence",
	subscribed = "presence", unsubscribed = "presence",
}

local function st2json(s)
	local t = {
		kind = s.name,
		type = s.attr.type,
		to = s.attr.to,
		from = s.attr.from,
		id = s.attr.id,
	};
	if s.name == "presence" and not s.attr.type then
		t.type = "available";
	end

	if t.to then
		t.to = jid.prep(t.to);
		if not t.to then return nil, "invalid-jid-to"; end
	end
	if t.from then
		t.from = jid.prep(t.from);
		if not t.from then return nil, "invalid-jid-from"; end
	end

	if t.type == "error" then
		local err_typ, err_condition, err_text = s:get_error();
		t.error = {
			type = err_typ,
			condition = err_condition,
			text = err_text
		};
		return t;
	end

	for k, typ in pairs(simple_types) do
		if typ == "text_tag" then
			t[k] = s:get_child_text(k);
		elseif typ[1] == "text_tag" then
			t[k] = s:get_child_text(typ[3], typ[2]);
		elseif typ[1] == "name" then
			local child = s:get_child(nil, typ[2]);
			if child then
				t[k] = child.name;
			end
		elseif typ[1] == "attr" then
			local child = s:get_child(typ[3], typ[2])
			if child then
				t[k] = child.attr[typ[4]];
			end
		elseif typ[1] == "bool_tag" then
			if s:get_child(typ[3], typ[2]) then
				t[k] = true;
			end
		elseif typ[1] == "func" then
			local child = s:get_child(typ[3], typ[2] or k);
			-- TODO handle err
			if child then
				t[k] = typ[4](child);
			end
		end
	end

	return t;
end

local function str(s)
	if type(s) == "string" then
		return s;
	end
end

local function json2st(t)
	if type(t) ~= "table" or not str(next(t)) then
		return nil, "invalid-json";
	end
	local kind = str(t.kind) or kind_by_type[str(t.type)];
	if not kind then
		for k, implied in pairs(implied_kinds) do
			if t[k] then
				kind = implied;
				break
			end
		end
	end

	local s = st.stanza(kind or "message", {
		type = t.type ~= "available" and str(t.type) or nil,
		to = str(t.to) and jid.prep(t.to);
		from = str(t.to) and jid.prep(t.from);
		id = str(t.id),
	});

	if t.to and not s.attr.to then
		return nil, "invalid-jid-to";
	end
	if t.from and not s.attr.from then
		return nil, "invalid-jid-from";
	end
	if kind == "iq" and not s.attr.type then
		s.attr.type = "get";
	end

	if type(t.error) == "table" then
		return st.error_reply(st.reply(s), str(t.error.type), str(t.error.condition), str(t.error.text));
	elseif t.type == "error" then
		s:text_tag("error", t.body, { code = t.error_code and tostring(t.error_code) });
		return s;
	end

	for k, v in pairs(t) do
		local typ = simple_types[k];
		if typ then
			if typ == "text_tag" then
				s:text_tag(k, v);
			elseif typ[1] == "text_tag" then
				s:text_tag(typ[3] or k, v, typ[2] and { xmlns = typ[2] });
			elseif typ[1] == "name" then
				s:tag(v, { xmlns = typ[2] }):up();
			elseif typ[1] == "attr" then
				s:tag(typ[3] or k, { xmlns = typ[2], [ typ[4] or k ] = v }):up();
			elseif typ[1] == "bool_tag" then
				s:tag(typ[3] or k, { xmlns = typ[2] }):up();
			elseif typ[1] == "func" then
				s:add_child(typ[5](v)):up();
			end
		end
	end

	s:reset();

	return s;
end

return {
	st2json = st2json;
	json2st = json2st;
};
