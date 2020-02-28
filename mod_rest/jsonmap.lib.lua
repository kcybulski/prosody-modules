local array = require "util.array";
local jid = require "util.jid";
local json = require "util.json";
local st = require "util.stanza";
local xml = require "util.xml";

local field_mappings; -- in scope for "func" mappings
field_mappings = {
	-- top level stanza attributes
	-- needed here to mark them as known fields
	kind = "attr",
	type = "attr",
	to = "attr",
	from = "attr",
	id = "attr",

	-- basic message
	body = "text_tag",
	subject = "text_tag",
	thread = "text_tag",

	-- basic presence
	show = "text_tag",
	status = "text_tag",
	priority = "text_tag",

	state = { type = "name", xmlns = "http://jabber.org/protocol/chatstates" },
	nick = { type = "text_tag", xmlns = "http://jabber.org/protocol/nick", tagname = "nick" },
	delay = { type = "attr", xmlns = "urn:xmpp:delay", tagname = "delay", attr = "stamp" },
	replace = { type = "attr", xmlns = "urn:xmpp:message-correct:0", tagname = "replace", attr = "id" },

	-- XEP-0045 MUC
	-- TODO history, password, ???
	join = { type = "bool_tag", xmlns = "http://jabber.org/protocol/muc", tagname = "x" },

	-- XEP-0071
	html = {
		type = "func", xmlns = "http://jabber.org/protocol/xhtml-im", tagname = "html",
		st2json = function (s) --> json string
			return (tostring(s:get_child("body", "http://www.w3.org/1999/xhtml")):gsub(" xmlns='[^']*'", "", 1));
		end;
		json2st = function (s) --> xml
			if type(s) == "string" then
				return assert(xml.parse("<x:html xmlns:x='http://jabber.org/protocol/xhtml-im' xmlns='http://www.w3.org/1999/xhtml'>" .. s .. "</x:html>"));
			end
		end;
	};

	-- XEP-0199: XMPP Ping
	ping = { type = "bool_tag", xmlns = "urn:xmpp:ping", tagname = "ping" },

	-- XEP-0092: Software Version
	version = { type = "func", xmlns = "jabber:iq:version", tagname = "query",
		st2json = function (s)
			return {
				name = s:get_child_text("name");
				version = s:get_child_text("version");
				os = s:get_child_text("os");
			}
		end,
		json2st = function (s)
			local v = st.stanza("query", { xmlns = "jabber:iq:version" });
			if type(s) == "table" then
				v:text_tag("name", s.name);
				v:text_tag("version", s.version);
				if s.os then
					v:text_tag("os", s.os);
				end
			end
			return v;
		end
	};

	-- XEP-0030
	disco = {
		type = "func", xmlns = "http://jabber.org/protocol/disco#info", tagname = "query",
		st2json = function (s) --> array of features
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
		json2st = function (s)
			if type(s) == "table" and s ~= json.null then
				local disco = st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#info", node = s.node });
				if s.identities then
					for _, identity in ipairs(s.identities) do
						disco:tag("identity", { category = identity.category, type = identity.type, name = identity.name }):up();
					end
				end
				if s.features then
					for _, feature in ipairs(s.features) do
						disco:tag("feature", { var = feature }):up();
					end
				end
				return disco;
			else
				return st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#info", });
			end
		end;
	};

	items = {
		type = "func", xmlns = "http://jabber.org/protocol/disco#items", tagname = "query",
		st2json = function (s) --> array of features | map with node
			if s.attr.node and s.tags[1] == nil then
				return { node = s.attr.node };
			end

			local items = array();
			for item in s:childtags("item") do
				items:push({ jid = item.attr.jid, node = item.attr.node, name = item.attr.name });
			end
			return items;
		end;
		json2st = function (s)
			if type(s) == "table" and s ~= json.null then
				local disco = st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#items", node = s.node });
				for _, item in ipairs(s) do
					if type(item) == "string" then
						disco:tag("item", { jid = item });
					elseif type(item) == "table" then
						disco:tag("item", { jid = item.jid, node = item.node, name = item.name });
					end
				end
				return disco;
			else
				return st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#items", });
			end
		end;
	};

	-- XEP-0050: Ad-Hoc Commands
	command = { type = "func", xmlns = "http://jabber.org/protocol/commands", tagname = "command",
		st2json = function (s)
			local cmd = {
				action = s.attr.action,
				node = s.attr.node,
				sessionid = s.attr.sessionid,
				status = s.attr.status,
			};
			local actions = s:get_child("actions");
			local note = s:get_child("note");
			local form = s:get_child("x", "jabber:x:data");
			if actions then
				cmd.actions = {
					execute = actions.attr.execute,
				};
				for action in actions:childtags() do
					cmd.actions[action.name] = true
				end
			elseif note then
				cmd.note = {
					type = note.attr.type;
					text = note:get_text();
				};
			end
			if form then
				cmd.form = field_mappings.dataform.st2json(form);
			end
			return cmd;
		end;
		json2st = function (s)
			if type(s) == "table" and s ~= json.null then
				local cmd = st.stanza("command", {
					xmlns = "http://jabber.org/protocol/commands",
					action = s.action,
					node = s.node,
					sessionid = s.sessionid,
					status = s.status,
				});
				if type(s.actions) == "table" then
					cmd:tag("actions", { execute = s.actions.execute });
					do
						if s.actions.next == true then
							cmd:tag("next"):up();
						end
						if s.actions.prev == true then
							cmd:tag("prev"):up();
						end
						if s.actions.complete == true then
							cmd:tag("complete"):up();
						end
					end
					cmd:up();
				elseif type(s.note) == "table" then
					cmd:text_tag("note", s.note.text, { type = s.note.type });
				end
				if s.form then
					cmd:add_child(field_mappings.dataform.json2st(s.form));
				elseif s.data then
					cmd:add_child(field_mappings.formdata.json2st(s.data));
				end
				return cmd;
			elseif type(s) == "string" then -- assume node
				return st.stanza("command", { xmlns = "http://jabber.org/protocol/commands", node = s });
			end
			-- else .. missing required attribute
		end;
	};

	-- XEP-0066: Out of Band Data
	oob_url = { type = "func", xmlns = "jabber:iq:oob", tagname = "query",
		st2json = function (s)
			return s:get_child_text("url");
		end;
		json2st = function (s)
			if type(s) == "string" then
				return st.stanza("query", { xmlns = "jabber:iq:oob" }):text_tag("url", s);
			end
		end;
	};

	-- XEP-0432: Simple JSON Messaging
	payload = { type = "func", xmlns = "urn:xmpp:json-msg:0", tagname = "payload",
		st2json = function (s)
			local rawjson = s:get_child_text("json", "urn:xmpp:json:0");
			if not rawjson then return nil, "missing-json-payload"; end
			local parsed, err = json.decode(rawjson);
			if not parsed then return nil, err; end
			return {
				datatype = s.attr.datatype;
				data = parsed;
			};
		end;
		json2st = function (s)
			if type(s) == "table" then
				return st.stanza("payload", { xmlns = "urn:xmpp:json-msg:0", datatype = s.datatype })
				:tag("json", { xmlns = "urn:xmpp:json:0" }):text(json.encode(s.data));
			end;
		end
	};

	-- XEP-0004: Data Forms
	dataform = {
		-- Generic and complete dataforms mapping
		type = "func", xmlns = "jabber:x:data", tagname = "x",
		st2json = function (s)
			local fields = array();
			local form = {
				type = s.attr.type;
				title = s:get_child_text("title");
				instructions = s:get_child_text("instructions");
				fields = fields;
			};
			for field in s:childtags("field") do
				local i = {
					var = field.attr.var;
					type = field.attr.type;
					label = field.attr.label;
					desc = field:get_child_text("desc");
					required = field:get_child("required") and true or nil;
					value = field:get_child_text("value");
				};
				if field.attr.type == "jid-multi" or field.attr.type == "list-multi" or field.attr.type == "text-multi" then
					local value = array();
					for v in field:childtags("value") do
						value:push(v:get_text());
					end
					if field.attr.type == "text-multi" then
						i.value = value:concat("\n");
					else
						i.value = value;
					end
				end
				if field.attr.type == "list-single" or field.attr.type == "list-multi" then
					local options = array();
					for o in field:childtags("option") do
						options:push({ label = o.attr.label, value = o:get_child_text("value") });
					end
					i.options = options;
				end
				fields:push(i);
			end
			return form;
		end;
		json2st = function (x)
			if type(x) == "table" and x ~= json.null then
				local form = st.stanza("x", { xmlns = "jabber:x:data", type = x.type });
				if x.title then
					form:text_tag("title", x.title);
				end
				if x.instructions then
					form:text_tag("instructions", x.instructions);
				end
				if type(x.fields) == "table" then
					for _, f in ipairs(x.fields) do
						if type(f) == "table" then
							form:tag("field", { var = f.var, type = f.type, label = f.label });
							if f.desc then
								form:text_tag("desc", f.desc);
							end
							if f.required == true then
								form:tag("required"):up();
							end
							if type(f.value) == "string" then
								form:text_tag("value", f.value);
							elseif type(f.value) == "table" then
								for _, v in ipairs(f.value) do
									form:text_tag("value", v);
								end
							end
							if type(f.options) == "table" then
								for _, o in ipairs(f.value) do
									if type(o) == "table" then
										form:tag("option", { label = o.label });
										form:text_tag("value", o.value);
										form:up();
									end
								end
							end
						end
					end
				end
				return form;
			end
		end;
	};

	-- Simpler mapping of dataform from JSON map
	formdata = { type = "func", xmlns = "jabber:x:data", tagname = "",
		st2json = function ()
			-- Tricky to do in a generic way without each form layout
			-- In the future, some well-known layouts might be understood
			return nil, "not-implemented";
		end,
		json2st = function (s, t)
			local form = st.stanza("x", { xmlns = "jabber:x:data", type = t });
			for k, v in pairs(s) do
				form:tag("field", { var = k });
				if type(v) == "string" then
					form:text_tag("value", v);
				elseif type(v) == "table" then
					for _, v_ in ipairs(v) do
						form:text_tag("value", v_);
					end
				end
			end
			return form;
		end
	};

	-- XEP-0039: Statistics Gathering
	stats = { type = "func", xmlns = "http://jabber.org/protocol/stats", tagname = "query",
		st2json = function (s)
			local o = array();
			for stat in s:childtags("stat") do
				o:push({
						name = stat.attr.name;
						unit = stat.attr.unit;
						value = stat.attr.value;
					});
			end
			return o;
		end;
		json2st = function (j)
			local stats = st.stanza("query", { xmlns = "http://jabber.org/protocol/stats" });
			if type(j) == "table" then
				for _, stat in ipairs(j) do
					stats:tag("stat", { name = stat.name, unit = stat.unit, value = stat.value }):up();
				end
			end
			return stats;
		end;
	};

};

local implied_kinds = {
	disco = "iq",
	items = "iq",
	ping = "iq",
	version = "iq",
	command = "iq",

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
		local error = s:get_child("error");
		local err_typ, err_condition, err_text = s:get_error();
		t.error = {
			type = err_typ,
			condition = err_condition,
			text = err_text,
			by = error.attr.by,
		};
		return t;
	end

	for k, mapping in pairs(field_mappings) do
		if mapping == "text_tag" then
			t[k] = s:get_child_text(k);
		elseif mapping.type == "text_tag" then
			t[k] = s:get_child_text(mapping.tagname, mapping.xmlns);
		elseif mapping.type == "name" then
			local child = s:get_child(nil, mapping.xmlns);
			if child then
				t[k] = child.name;
			end
		elseif mapping.type == "attr" then
			local child = s:get_child(mapping.tagname, mapping.xmlns);
			if child then
				t[k] = child.attr[mapping.attr];
			end
		elseif mapping.type == "bool_tag" then
			if s:get_child(mapping.tagname, mapping.xmlns) then
				t[k] = true;
			end
		elseif mapping.type == "func" and mapping.st2json then
			local child = s:get_child(mapping.tagname, mapping.xmlns or k);
			-- TODO handle err
			if child then
				t[k] = mapping.st2json(child);
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
		return st.error_reply(st.reply(s), str(t.error.type), str(t.error.condition), str(t.error.text), str(t.error.by));
	elseif t.type == "error" then
		s:text_tag("error", t.body, { code = t.error_code and tostring(t.error_code) });
		return s;
	end

	for k, v in pairs(t) do
		local mapping = field_mappings[k];
		if mapping then
			if mapping == "text_tag" then
				s:text_tag(k, v);
			elseif mapping == "attr" then -- luacheck: ignore 542
				-- handled already
			elseif mapping.type == "text_tag" then
				s:text_tag(mapping.tagname or k, v, mapping.xmlns and { xmlns = mapping.xmlns });
			elseif mapping.type == "name" then
				s:tag(v, { xmlns = mapping.xmlns }):up();
			elseif mapping.type == "attr" then
				s:tag(mapping.tagname or k, { xmlns = mapping.xmlns, [mapping.attr or k] = v }):up();
			elseif mapping.type == "bool_tag" then
				s:tag(mapping.tagname or k, { xmlns = mapping.xmlns }):up();
			elseif mapping.type == "func" and mapping.json2st then
				s:add_child(mapping.json2st(v)):up();
			end
		else
			return nil, "unknown-field";
		end
	end

	s:reset();

	return s;
end

return {
	st2json = st2json;
	json2st = json2st;
};
