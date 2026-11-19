# AllowTrustOp.asset is an AssetCode (type + 4 or 12 code bytes, no issuer),
# but stellar_base decodes it as an Asset (type + code + issuer AccountID).
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

# Operation 0 of pubnet tx 50460006:157 (AllowTrustOp: trustor GDABKB..R4OQ,
# asset "FIL", authorize 0), 48 bytes, re-encoded by rs-stellar-xdr 30.0.0.
op = Base.decode64!("AAAAAMAVBz29LWmasr2PZIvhrfNnkSB023MlskLj64kdWIo4AAAAAUZJTAAAAAAA")
R.try_decode("A. real AllowTrustOp, 48 bytes", fn -> XDR.Operations.AllowTrust.decode_xdr(op) end)

# Same op with authorize = 1 (AUTHORIZED_FLAG), equally valid.
op1 = binary_part(op, 0, 44) <> <<0, 0, 0, 1>>
R.try_decode("B. same op, authorize = 1", fn -> XDR.Operations.AllowTrust.decode_xdr(op1) end)

# The same 48 bytes followed by the next 36 bytes of the real envelope (the
# start of the following Clawback operation). The decoder takes authorize = 0
# as a PublicKeyType, 32 bytes of the next operation as an "issuer", and 4
# more as "authorize", and reports success.
next36 = Base.decode16!("00000000000000130000000146494C0000000000190BB50BD22BFC576640606EFA22480D")
{:ok, {v, rest}} = XDR.Operations.AllowTrust.decode_xdr(op <> next36)
%{asset_code: %{asset: %{issuer: %{account_id: %{public_key: %{datum: issuer}}}}}, authorize: %{datum: auth}} = v
IO.puts("C. 48 + 36 bytes: decoded OK, #{byte_size(rest)} bytes left")
IO.puts("  issuer the SDK invented: #{StellarBase.StrKey.encode!(issuer, :ed25519_public_key)} (#{Base.encode16(issuer, case: :lower)})")
IO.puts("  authorize the SDK reports: #{auth} (the real value is 0)")

# The whole real envelope (576 bytes) that rs-stellar-xdr, go, js and python decode.
env = Base.decode64!("AAAAAgAAAAAZC7UL0iv8V2ZAYG76IkgNMVt2p7lxuZpnW/BtybQzPgAADhAC2HqsAACLLwAAAAEAAAAAAAAAAAAAAABl1RSKAAAAAAAAAAYAAAAAAAAABwAAAADAFQc9vS1pmrK9j2SL4a3zZ5EgdNtzJbJC4+uJHViKOAAAAAFGSUwAAAAAAAAAAAAAAAATAAAAAUZJTAAAAAAAGQu1C9Ir/FdmQGBu+iJIDTFbdqe5cbmaZ1vwbcm0Mz4AAAAAwBUHPb0taZqyvY9ki+Gt82eRIHTbcyWyQuPriR1YijgAAAAAAKO0KAAAAAAAAAAHAAAAAMAVBz29LWmasr2PZIvhrfNnkSB023MlskLj64kdWIo4AAAAAUZJTAAAAAABAAAAAAAAAAcAAAAAwBUHPb0taZqyvY9ki+Gt82eRIHTbcyWyQuPriR1YijgAAAABWE1SAAAAAAAAAAAAAAAAEwAAAAFYTVIAAAAAABkLtQvSK/xXZkBgbvoiSA0xW3anuXG5mmdb8G3JtDM+AAAAAMAVBz29LWmasr2PZIvhrfNnkSB023MlskLj64kdWIo4AAAAAAF/yUoAAAAAAAAABwAAAADAFQc9vS1pmrK9j2SL4a3zZ5EgdNtzJbJC4+uJHViKOAAAAAFYTVIAAAAAAQAAAAAAAAABybQzPgAAAECMhaPID97yWNH/saF+nrdWME0DZJ4kHYO/v+j3yAhxSQ10cWl+kELtenNxuwQ/3ZSBW/K5BqqargUXHMgl83YH")
R.try_decode("D. real envelope 50460006:157", fn -> XDR.TransactionEnvelope.decode_xdr(env) end)
