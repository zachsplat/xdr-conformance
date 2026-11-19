# Shared by every repro: install the published package and print helpers.
Mix.install([{:stellar_base, "== 0.17.0"}])
IO.puts("stellar_base #{Application.spec(:stellar_base, :vsn)}, elixir_xdr #{Application.spec(:elixir_xdr, :vsn)}")

defmodule R do
  # Call a decode_xdr/1 and show either its return value or what it raised.
  def try_decode(label, fun) do
    result =
      try do
        fun.()
      rescue
        e -> {:raised, e.__struct__, Exception.message(e)}
      end

    IO.puts("#{label}:\n  " <> inspect(result, limit: 12, printable_limit: 64))
    result
  end
end
