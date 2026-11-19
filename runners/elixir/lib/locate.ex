defmodule Locate do
  @moduledoc """
  Debug helper, not part of the protocol: for each request on stdin that fails
  to decode, print the chain of stellar_base decode_xdr calls open at the first
  failure and the byte offset where each started. Uses Erlang call tracing.

      mix run --no-compile -e "Locate.main()" < requests.jsonl
  """

  def main do
    :io.setopts(:standard_io, binary: true, encoding: :latin1)
    :erlang.system_flag(:backtrace_depth, 200)

    IO.binstream(:standard_io, :line)
    |> Stream.reject(&(String.trim(&1) == ""))
    |> Enum.each(fn line ->
      req = Jason.decode!(line)
      raw = Base.decode64!(req["b64"])
      IO.puts("== #{req["id"]} (#{byte_size(raw)} bytes)")
      if System.get_env("LOCATE_TRACE") == "1", do: IO.puts(locate(req["type"], raw))
      IO.puts(stack_chain(req["type"], raw))
    end)
  end

  def locate(type, raw) do
    mods =
      for m <- elem(:application.get_key(:stellar_base, :modules), 1),
          function_exported?(m, :decode_xdr, 2),
          do: m

    total = byte_size(raw)
    me = self()
    tracer = spawn(fn -> collect(me, [], nil, []) end)
    target = spawn(fn -> receive(do: (:go -> run(type, raw))) end)
    :erlang.trace(target, true, [:call, {:tracer, tracer}])
    for m <- mods, f <- [:decode_xdr, :decode_xdr!],
        do: :erlang.trace_pattern({m, f, 2}, [{:_, [], [{:exception_trace}]}], [:local])
    ref = Process.monitor(target)
    send(target, :go)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
    :erlang.trace_delivered(target)
    receive do: ({:trace_delivered, _, _} -> :ok)
    send(tracer, {:done, self()})
    receive do
      {:result, nil} ->
        "no failure seen"

      {:result, {stack, mod, err}} ->
        lines =
          stack
          |> Enum.reverse()
          |> Enum.map(fn {m, left} -> "  @#{total - left} #{inspect(m)}" end)

        Enum.join(lines, "\n") <> "\n  first failure in #{inspect(mod)}: #{inspect(err) |> String.slice(0, 300)}"
    end
  end

  # The StellarBase frames open when the decoder raised, innermost last.
  def stack_chain(type, raw) do
    {:ok, c} = Facts.codec(type)

    try do
      c.decode.(raw)
      "  (no exception raised)"
    rescue
      e ->
        frames =
          for {m, f, a, _} <- __STACKTRACE__,
              String.starts_with?(inspect(m), "StellarBase"),
              do: "#{inspect(m) |> String.replace("StellarBase.XDR.", "")}.#{f}/#{if is_list(a), do: length(a), else: a}"

        "  raise #{inspect(e.__struct__)} through: " <> (frames |> Enum.reverse() |> Enum.dedup() |> Enum.join(" > "))
    end
  end

  defp run(type, raw) do
    try do
      {:ok, c} = Facts.codec(type)
      c.decode.(raw)
    rescue
      _ -> :error
    end
  end

  defp collect(parent, stack, first, last) do
    receive do
      {:trace, _, :call, {m, _f, [bytes, _]}} ->
        st = [{m, byte_size(bytes)} | stack]
        collect(parent, st, first, st)

      {:trace, _, :return_from, {m, _f, 2}, ret} ->
        first =
          case {first, ret} do
            {nil, {:error, e}} -> {stack, m, e}
            _ -> first
          end

        collect(parent, tl_safe(stack), first, last)

      {:trace, _, :exception_from, {m, _f, 2}, e} ->
        first = first || {stack, m, e}
        collect(parent, tl_safe(stack), first, last)

      {:done, p} ->
        send(p, {:result, first || (last != [] && {last, :last_call_before_raise, nil}) || nil})

      _ ->
        collect(parent, stack, first, last)
    end
  end

  defp tl_safe([]), do: []
  defp tl_safe([_ | t]), do: t
end
