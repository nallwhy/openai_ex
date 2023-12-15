defmodule OpenaiEx.HttpSse do
  @moduledoc false
  require Logger

  # based on
  # https://gist.github.com/zachallaun/88aed2a0cef0aed6d68dcc7c12531649

  @doc false
  def post(openai = %OpenaiEx{}, url, json: json) do
    me = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        on_chunk = fn {:data, data}, acc ->
          send(me, {:chunk, {:data, data}, ref})

          {:cont, acc}
        end

        Req.post!(openai.base_url <> url,
          headers: OpenaiEx.Http.headers(openai),
          json: json,
          finch: OpenaiEx.Finch,
          into: on_chunk
        )

        send(me, {:done, ref})
      end)

    Stream.resource(fn -> {"", ref, task} end, &next_sse/1, fn {_data, _ref, task} ->
      Task.shutdown(task)
    end)
  end

  @doc false
  defp next_sse({acc, ref, task}) do
    receive do
      {:chunk, {:data, evt_data}, ^ref} ->
        {tokens, next_acc} = tokenize_data(evt_data, acc)
        {[tokens], {next_acc, ref, task}}

      {:done, ^ref} ->
        if acc != "" do
          Logger.warning(inspect(Jason.decode!(acc)))
        end

        {:halt, {acc, ref, task}}
    end
  end

  @doc false
  defp tokenize_data(evt_data, acc) do
    if String.contains?(evt_data, "\n\n") do
      {remaining, token_chunks} = (acc <> evt_data) |> String.split("\n\n") |> List.pop_at(-1)

      tokens =
        token_chunks
        |> Enum.map(fn chunk -> extract_token(chunk) end)
        |> Enum.filter(fn %{data: data} -> data != "[DONE]" end)
        |> Enum.map(fn %{data: data} -> %{data: Jason.decode!(data)} end)

      {tokens, remaining}
    else
      {[], acc <> evt_data}
    end
  end

  @doc false
  defp extract_token(line) do
    [field | rest] = String.split(line, ": ", parts: 2)

    case field do
      "data" -> %{data: Enum.join(rest, "") |> String.replace_prefix(" ", "")}
    end
  end
end
