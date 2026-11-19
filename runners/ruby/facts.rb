# Conformance adapter for the Ruby SDK (astroband/ruby-stellar-sdk):
# gem stellar-base (generated XDR classes on top of the xdr gem).
# Same JSONL protocol as runners/python/facts.py. stellar-base has no SEP-51
# JSON form, so results carry decode, round-trip and hash only, plus
# "strkeys": every account, muxed account and signer key in the decoded value,
# rendered through the SDK's own strkey code and sorted, so the strkey and
# muxed id rendering can be checked against the SEP-51 JSON of the reference.
#
# Run (see run.sh in this directory):
#   ruby facts.rb < requests.jsonl > results.jsonl
require "json"
require "base64"
require "stellar-base"

TYPES = Stellar.constants.each_with_object({}) { |c, h| h[c.to_s.downcase] = c }

def xdr_type(name)
  c = TYPES[name.to_s.downcase]
  raise ArgumentError, "unknown type #{name}" if c.nil?
  Stellar.const_get(c)
end

STRKEY = Stellar::Util::StrKey

def signer_strkey(sk)
  case sk.arm
  when :ed25519 then STRKEY.check_encode(:account_id, sk.value)
  when :pre_auth_tx then STRKEY.check_encode(:pre_auth_tx, sk.value)
  when :hash_x then STRKEY.check_encode(:hash_x, sk.value)
  when :ed25519_signed_payload then STRKEY.encode_signed_payload(sk.value)
  end
end

# Iterative walk: deep values must not exhaust the Ruby stack here.
def collect_strkeys(root)
  out = []
  stack = [root]
  until stack.empty?
    v = stack.pop
    case v
    when Stellar::MuxedAccount then out << STRKEY.encode_muxed_account(v)
    when Stellar::PublicKey then out << Stellar::Convert.pk_to_address(v)
    when Stellar::SignerKey then out << signer_strkey(v)
    when XDR::Struct then stack.concat(v.attributes.values)
    when XDR::Union then stack << v.value
    when Array then stack.concat(v)
    end
  end
  out.compact.sort
end

def tx_hash(env, passphrase)
  Stellar.on_network(passphrase) { env.tx.hash.unpack1("H*") }
rescue Exception => e # rubocop:disable Lint/RescueException
  "error: #{e.class}: #{e.message}"[0, 200]
end

def decode(req)
  out = {"id" => req["id"]}
  begin
    raw = Base64.strict_decode64(req["b64"])
    t = xdr_type(req["type"])
    v = t.from_xdr(raw)
    back = t.to_xdr(v)
  rescue SystemStackError => e
    out.update("ok" => false, "error" => "SystemStackError (Ruby stack exhausted): #{e.message}"[0, 300])
    return out
  rescue Exception => e # rubocop:disable Lint/RescueException
    out.update("ok" => false, "error" => "#{e.class}: #{e.message}"[0, 300])
    return out
  end
  eq = back.b == raw.b
  out.update("ok" => true, "roundtrip_equal" => eq)
  out["reencoded_b64"] = Base64.strict_encode64(back) unless eq
  if t == Stellar::TransactionEnvelope && req["network"]
    out["hash"] = tx_hash(v, req["network"])
  end
  begin
    out["strkeys"] = collect_strkeys(v)
  rescue Exception => e # rubocop:disable Lint/RescueException
    out["strkeys_error"] = "#{e.class}: #{e.message}"[0, 200]
  end
  out
end

$stdout.sync = false
$stdin.each_line do |line|
  next if line.strip.empty?
  begin
    req = JSON.parse(line)
  rescue JSON::ParserError
    next
  end
  res = decode(req)
  $stdout.write(JSON.generate(res) + "\n")
end
$stdout.flush
