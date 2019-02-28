local base64 = require "util.encodings".base64;
local digest = require "openssl.digest";
local hmac = require "openssl.hmac";
local luatz = require "luatz";
local otp = require "otp";

local DIGEST_TYPE = "SHA256";
local OTP_DEVIATION = 1;
local OTP_DIGITS = 8;
local OTP_INTERVAL = 30;

local nonce_cache = {};

function check_nonce(jid, otp, nonce)
	-- We cache all nonces used per OTP, to ensure that a token cannot be used
	-- more than once.
	--
	-- We assume that the OTP is valid in the current time window. This is the
	-- case because we only call check_nonce *after* the OTP has been verified.
	--
	-- We only store one OTP per JID, so if a new OTP comes in, we wipe the
	-- previous OTP and its cached nonces.
	if nonce_cache[jid] == nil or nonce_cache[jid][otp] == nil then
		nonce_cache[jid] = {}
		nonce_cache[jid][otp] = {}
		nonce_cache[jid][otp][nonce] = true
		return true;
	end
	if nonce_cache[jid][otp][nonce] == true then
		return false;
	else
		nonce_cache[jid][otp][nonce] = true;
		return true;
	end
end


function verify_token(username, password, realm, otp_seed, token_secret, log)
	if (realm ~= module.host) then
		log("debug", "Verification failed: realm ~= module.host");
		return false;
	end

	local totp = otp.new_totp_from_key(otp_seed, OTP_DIGITS, OTP_INTERVAL)
	local token = string.match(password, "(%d+) ")
	local otp = token:sub(1,8)
	local nonce = token:sub(9)
	local signature = base64.decode(string.match(password, " (.+)"))
	local jid = username.."@"..realm

	if totp:verify(otp, OTP_DEVIATION, luatz.gmtime(luatz.time())) then
		log("debug", "The TOTP was verified");
		local hmac_ctx = hmac.new(token_secret, DIGEST_TYPE)
		if signature == hmac_ctx:final(otp..nonce..jid) then
			log("debug", "The key was verified");
			if check_nonce(jid, otp, nonce) then
				log("debug", "The nonce was verified");
				return true;
			end
		end
	end
	log("debug", "Verification failed");
	return false;
end

return {
	OTP_DEVIATION = OTP_DIGITS,
	OTP_DIGITS = OTP_DIGITS,
	OTP_INTERVAL = OTP_INTERVAL,
	DIGEST_TYPE = DIGEST_TYPE,
	verify_token = verify_token;
}
