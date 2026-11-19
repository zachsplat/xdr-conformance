# LiquidityPoolEntry is { PoolID liquidityPoolID; body }. stellar_base declares
# the fields in the opposite order (body first, then liquidity_pool_id).
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

# The LiquidityPoolEntry of pool LAFEERBX..KAHA (AMM / yUSDC) from the result
# meta of pubnet tx 40000000:21, re-encoded by rs-stellar-xdr 30.0.0 (148 bytes).
lp = Base.decode64!("CkJENwbUGTswvLt83GcwYEScKcCW2v4Z89HBHJh9bzUAAAAAAAAAAUFNTQAAAAAAIw+7qXhHoY6kKXOl1sf/w4kL6vxYZH7dMuNZWefIWmAAAAACeVVTREMAAAAAAAAAAAAAAM062kzjDS5P+fW5F9nCOTSPRGUSC5NLY3A9tdoTi3LZAAAAHgAAAAsZ3jlhAAAAAAUuo+sAAAAAdLhWNgAAAAAAAAAP")
R.try_decode("A. real LiquidityPoolEntry", fn -> XDR.LiquidityPoolEntry.decode_xdr(lp) end)

# Move the 32-byte pool id from the front to the back: now the SDK accepts it,
# which shows it reads the fields in the wrong order.
swapped = binary_part(lp, 32, byte_size(lp) - 32) <> binary_part(lp, 0, 32)
{:ok, {v, ""}} = XDR.LiquidityPoolEntry.decode_xdr(swapped)
IO.puts("B. fields swapped by hand: decoded OK, pool id = #{Base.encode16(v.liquidity_pool_id.value, case: :lower) |> String.slice(0, 16)}...")
