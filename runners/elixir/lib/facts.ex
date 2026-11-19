defmodule Facts do
  @moduledoc """
  Conformance adapter for kommitters/stellar_base (Elixir), same JSONL protocol
  as runners/python/facts.py and runners/go/main.go.

  Request:  {"id", "op": "decode", "type", "b64", "network"?}
  Result:   {"id", "ok", "error"?, "roundtrip_equal", "reencoded_b64"?, "hash"?,
             "strkeys"?}

  stellar_base has no SEP-51 JSON form, so no "json" is written. "strkeys" is
  an extra field: SEP-23 strkeys the SDK's StrKey module writes for the
  account fields of an envelope, keyed by their path in the SEP-51 JSON, so
  they can be checked against rs-stellar-xdr's JSON.

  Notes on choices this adapter makes (see expansion/elixir/REPORT.md):
  - decode_xdr/1 returns {value, rest}. Like every other adapter in the kit
    (whole-message decoding), leftover bytes are reported as a decode error.
  - stellar_base has no TransactionResultMeta / TransactionResultMetaV1 /
    TransactionResultPair module. The adapter decodes those types field by
    field with the SDK's own modules (Hash, TransactionResult,
    LedgerEntryChanges, TransactionMeta, ExtensionPoint) and re-encodes them
    the same way.
  - stellar_base has no transaction model with a hash function (that lives in
    the separate stellar_sdk package). The hash is computed by building the
    SDK's TransactionSignaturePayload struct from the decoded envelope and
    taking sha256 of the SDK's encoding of it. A v0 envelope is converted to
    the SDK's Transaction struct first, as stellar-core does.
  - Each request runs in its own process with a timeout and a heap cap, so a
    hang or a blow-up is reported as an error instead of killing the runner.
  """

  alias StellarBase.XDR

  @timeout_ms String.to_integer(System.get_env("XDRCONF_TIMEOUT_MS") || "30000")
  # words; 8 bytes each. 2^27 words = 1 GiB
  @max_heap String.to_integer(System.get_env("XDRCONF_MAX_HEAP_WORDS") || "134217728")

  def main do
    :io.setopts(:standard_io, binary: true, encoding: :latin1)
    {:ok, sup} = Task.Supervisor.start_link()
    conc = String.to_integer(System.get_env("XDRCONF_CONCURRENCY") || "#{System.schedulers_online()}")

    IO.binstream(:standard_io, :line)
    |> Stream.reject(&(String.trim(&1) == ""))
    |> Stream.map(&parse_line/1)
    |> then(fn reqs ->
      Task.Supervisor.async_stream_nolink(sup, reqs, &run_one/1,
        max_concurrency: conc,
        ordered: true,
        timeout: @timeout_ms,
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
    end)
    |> Stream.each(fn
      {:ok, res} ->
        IO.binwrite(:standard_io, Jason.encode!(res) <> "\n")

      {:exit, {req, reason}} ->
        id = if is_map(req), do: req["id"], else: nil
        msg = "runner: request process exited: #{inspect(reason) |> String.slice(0, 200)}"
        IO.binwrite(:standard_io, Jason.encode!(%{id: id, ok: false, error: msg}) <> "\n")
    end)
    |> Stream.run()
  end

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, req} -> req
      {:error, e} -> %{"id" => nil, "_bad" => Exception.message(e)}
    end
  end

  def run_one(%{"_bad" => msg} = req), do: %{id: req["id"], ok: false, error: "bad request: #{msg}"}

  def run_one(req) do
    Process.flag(:max_heap_size, %{size: @max_heap, kill: true, error_logger: false})

    try do
      decode(req)
    rescue
      e -> %{id: req["id"], ok: false, error: clip("#{inspect(e.__struct__)}: #{Exception.message(e)}")}
    catch
      kind, val -> %{id: req["id"], ok: false, error: clip("#{kind}: #{inspect(val)}")}
    end
  end

  defp clip(s), do: String.slice(s, 0, 300)

  defp decode(req) do
    id = req["id"]

    with {:ok, raw} <- b64(req["b64"]),
         {:ok, codec} <- codec(req["type"]),
         {:ok, {value, rest}} <- codec.decode.(raw),
         :ok <- no_rest(rest),
         {:ok, back} <- codec.encode.(value) do
      out = %{id: id, ok: true, roundtrip_equal: back == raw}
      out = if back == raw, do: out, else: Map.put(out, :reencoded_b64, Base.encode64(back))

      if req["type"] == "TransactionEnvelope" do
        out = Map.put(out, :strkeys, envelope_strkeys(value))

        if req["network"],
          do: Map.put(out, :hash, tx_hash(value, req["network"])),
          else: out
      else
        out
      end
    else
      {:error, reason} -> %{id: id, ok: false, error: clip(fmt(reason))}
      other -> %{id: id, ok: false, error: clip("unexpected: #{inspect(other)}")}
    end
  end

  defp fmt(reason) when is_binary(reason), do: reason
  defp fmt(reason), do: inspect(reason)

  defp b64(s) when is_binary(s) do
    case Base.decode64(s) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, "bad base64"}
    end
  end

  defp b64(_), do: {:error, "missing b64"}

  defp no_rest(""), do: :ok
  defp no_rest(rest), do: {:error, "trailing bytes: #{byte_size(rest)} left after decode"}

  # ---- type lookup ---------------------------------------------------------

  def codec("TransactionResultMeta") do
    {:ok, seq_codec([XDR.Hash, XDR.TransactionResult, XDR.LedgerEntryChanges, XDR.TransactionMeta])}
  end

  def codec("TransactionResultMetaV1") do
    {:ok,
     seq_codec([
       XDR.ExtensionPoint,
       XDR.Hash,
       XDR.TransactionResult,
       XDR.LedgerEntryChanges,
       XDR.TransactionMeta,
       XDR.LedgerEntryChanges
     ])}
  end

  def codec(type) when is_binary(type) do
    mod = Module.concat(XDR, type)

    if Code.ensure_loaded?(mod) and function_exported?(mod, :decode_xdr, 1) do
      {:ok,
       %{
         decode: fn raw -> mod.decode_xdr(raw) end,
         encode: fn v -> mod.encode_xdr(v) end
       }}
    else
      {:error, "type not in stellar_base: #{type}"}
    end
  end

  def codec(_), do: {:error, "missing type"}

  # A struct the SDK does not model, decoded as its fields in order.
  defp seq_codec(mods) do
    %{
      decode: fn raw ->
        Enum.reduce_while(mods, {:ok, {[], raw}}, fn mod, {:ok, {acc, bytes}} ->
          case mod.decode_xdr(bytes) do
            {:ok, {v, rest}} -> {:cont, {:ok, {[v | acc], rest}}}
            {:error, e} -> {:halt, {:error, "#{inspect(mod)}: #{fmt(e)}"}}
          end
        end)
        |> case do
          {:ok, {acc, rest}} -> {:ok, {Enum.reverse(acc), rest}}
          e -> e
        end
      end,
      encode: fn values ->
        Enum.zip(mods, values)
        |> Enum.reduce_while({:ok, []}, fn {mod, v}, {:ok, acc} ->
          case mod.encode_xdr(v) do
            {:ok, b} -> {:cont, {:ok, [b | acc]}}
            {:error, e} -> {:halt, {:error, "encode #{inspect(mod)}: #{fmt(e)}"}}
          end
        end)
        |> case do
          {:ok, parts} -> {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}
          e -> e
        end
      end
    }
  end

  # ---- transaction hash through the SDK's structs --------------------------

  def tx_hash(%XDR.TransactionEnvelope{envelope: env, type: %{identifier: t}}, passphrase) do
    network_id = XDR.Hash.new(:crypto.hash(:sha256, passphrase))

    tagged =
      case t do
        :ENVELOPE_TYPE_TX_V0 ->
          XDR.TransactionSignaturePayloadTaggedTransaction.new(
            v0_to_tx(env.tx),
            XDR.EnvelopeType.new(:ENVELOPE_TYPE_TX)
          )

        :ENVELOPE_TYPE_TX ->
          XDR.TransactionSignaturePayloadTaggedTransaction.new(
            env.tx,
            XDR.EnvelopeType.new(:ENVELOPE_TYPE_TX)
          )

        :ENVELOPE_TYPE_TX_FEE_BUMP ->
          XDR.TransactionSignaturePayloadTaggedTransaction.new(
            env.tx,
            XDR.EnvelopeType.new(:ENVELOPE_TYPE_TX_FEE_BUMP)
          )
      end

    case XDR.TransactionSignaturePayload.new(network_id, tagged) |> XDR.TransactionSignaturePayload.encode_xdr() do
      {:ok, bytes} -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      {:error, e} -> "error: #{fmt(e)}"
    end
  rescue
    e -> clip("error: #{inspect(e.__struct__)}: #{Exception.message(e)}")
  end

  defp v0_to_tx(%XDR.TransactionV0{} = v0) do
    source = XDR.MuxedAccount.new(v0.source_account_ed25519, XDR.CryptoKeyType.new(:KEY_TYPE_ED25519))

    pre =
      case v0.time_bounds do
        %{time_bounds: nil} -> XDR.Preconditions.new(XDR.Void.new(), XDR.PreconditionType.new(:PRECOND_NONE))
        %{time_bounds: tb} -> XDR.Preconditions.new(tb, XDR.PreconditionType.new(:PRECOND_TIME))
      end

    XDR.Transaction.new(source, v0.fee, v0.seq_num, pre, v0.memo, v0.operations, XDR.TransactionExt.new(XDR.Void.new(), 0))
  end

  # ---- strkeys of account fields, keyed by SEP-51 JSON path ----------------

  def envelope_strkeys(%XDR.TransactionEnvelope{envelope: env, type: %{identifier: t}}) do
    try do
      case t do
        :ENVELOPE_TYPE_TX_V0 ->
          %{"tx_v0.tx.source_account_ed25519" => g(env.tx.source_account_ed25519)}
          |> Map.merge(ops_strkeys("tx_v0.tx.operations", env.tx.operations))

        :ENVELOPE_TYPE_TX ->
          tx_strkeys("tx.tx", env.tx)

        :ENVELOPE_TYPE_TX_FEE_BUMP ->
          inner = env.tx.inner_tx.envelope

          %{"tx_fee_bump.tx.fee_source" => muxed(env.tx.fee_source)}
          |> Map.merge(tx_strkeys("tx_fee_bump.tx.inner_tx.tx.tx", inner.tx))
      end
    rescue
      e -> %{"_error" => clip("#{inspect(e.__struct__)}: #{Exception.message(e)}")}
    end
  end

  defp tx_strkeys(prefix, tx) do
    %{"#{prefix}.source_account" => muxed(tx.source_account)}
    |> Map.merge(ops_strkeys("#{prefix}.operations", tx.operations))
  end

  defp ops_strkeys(prefix, %{operations: ops}) do
    ops
    |> Enum.with_index()
    |> Enum.flat_map(fn {op, i} ->
      p = "#{prefix}.#{i}"

      src =
        case op.source_account do
          %XDR.OptionalMuxedAccount{source_account: nil} -> []
          %XDR.OptionalMuxedAccount{source_account: m} -> [{"#{p}.source_account", muxed(m)}]
        end

      src ++ body_strkeys("#{p}.body", op.body)
    end)
    |> Map.new()
  end

  defp body_strkeys(p, %{type: %{identifier: kind}, value: v}) do
    case kind do
      :PAYMENT -> [{"#{p}.payment.destination", muxed(v.destination)}]
      :PATH_PAYMENT_STRICT_RECEIVE -> [{"#{p}.path_payment_strict_receive.destination", muxed(v.destination)}]
      :PATH_PAYMENT_STRICT_SEND -> [{"#{p}.path_payment_strict_send.destination", muxed(v.destination)}]
      :ACCOUNT_MERGE -> [{"#{p}.account_merge", muxed(v)}]
      :CLAWBACK -> [{"#{p}.clawback.from", muxed(v.from)}]
      :CREATE_ACCOUNT -> [{"#{p}.create_account.destination", account_id(v.destination)}]
      _ -> []
    end
  end

  defp body_strkeys(_p, _), do: []

  defp g(%XDR.UInt256{datum: k}), do: StellarBase.StrKey.encode!(k, :ed25519_public_key)

  defp account_id(%XDR.AccountID{account_id: %XDR.PublicKey{public_key: k}}), do: g(k)

  defp muxed(%XDR.MuxedAccount{type: %{identifier: :KEY_TYPE_ED25519}, account: k}), do: g(k)

  defp muxed(%XDR.MuxedAccount{type: %{identifier: :KEY_TYPE_MUXED_ED25519}, account: m}) do
    %XDR.MuxedAccountMed25519{id: %{datum: id}, ed25519: %XDR.UInt256{datum: k}} = m
    StellarBase.StrKey.encode!(k <> <<id::big-unsigned-64>>, :muxed_account)
  end
end
