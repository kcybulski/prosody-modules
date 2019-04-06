local dataforms = require "util.dataforms";
local adhoc_util = require "util.adhoc";
local serialization = require "util.serialization";

local adhoc_new = module:require "adhoc".new;

-- Dataform borrowed from Prosodys busted test for util.dataforms
local form = dataforms.new({
	title = "form-title",
	instructions = "form-instructions",
	{
		type = "hidden",
		name = "FORM_TYPE",
		value = "xmpp:prosody.im/spec/util.dataforms#1",
	};
	{
		type = "fixed",
		label = "fixed-label",
		name = "fixed-field#1",
		value = "fixed-value",
	},
	{
		type = "hidden",
		label = "hidden-label",
		name = "hidden-field",
		value = "hidden-value",
	},
	{
		type = "text-single",
		label = "text-single-label",
		name = "text-single-field",
		value = "text-single-value",
	},
	{
		type = "text-multi",
		label = "text-multi-label",
		name = "text-multi-field",
		value = "text\nmulti\nvalue",
	},
	{
		type = "text-private",
		label = "text-private-label",
		name = "text-private-field",
		value = "text-private-value",
	},
	{
		type = "boolean",
		label = "boolean-label",
		name = "boolean-field",
		value = true,
	},
	{
		type = "fixed",
		label = "fixed-label",
		name = "fixed-field#2",
		value = "fixed-value",
	},
	{
		type = "list-multi",
		label = "list-multi-label",
		name = "list-multi-field",
		value = {
			"list-multi-option-value#1",
			"list-multi-option-value#3",
		},
		options = {
			{
				label = "list-multi-option-label#1",
				value = "list-multi-option-value#1",
				default = true,
			},
			{
				label = "list-multi-option-label#2",
				value = "list-multi-option-value#2",
				default = false,
			},
			{
				label = "list-multi-option-label#3",
				value = "list-multi-option-value#3",
				default = true,
			},
		}
	},
	{
		type = "jid-single",
		label = "jid-single-label",
		name = "jid-single-field",
		value = "jid@single/value",
	},
	{
		type = "jid-multi",
		label = "jid-multi-label",
		name = "jid-multi-field",
		value = {
			"jid@multi/value#1",
			"jid@multi/value#2",
		},
	},
	{
		type = "list-single",
		label = "list-single-label",
		name = "list-single-field",
		value = "list-single-value",
		options = {
			"list-single-value",
			"list-single-value#2",
			"list-single-value#3",
		}
	},
})

local function handler(fields, err, data) -- luacheck: ignore 212/data
		return {
			status = "completed",
			info = "Data was:\n"
				.. serialization.serialize(err or fields),
		};
end

module:provides("adhoc",
	adhoc_new("Dataforms Demo",
		"xmpp:zash.se/mod_adhoc_dataforms_demo#form",
		adhoc_util.new_simple_form(form, handler)));
