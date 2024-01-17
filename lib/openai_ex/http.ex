defmodule OpenaiEx.Http do
  @moduledoc false
  require Logger

  @doc false
  def headers(openai = %OpenaiEx{}) do
    base = [{"Authorization", "Bearer #{openai.token}"}]

    org =
      if is_nil(openai.organization), do: [], else: [{"OpenAI-Organization", openai.organization}]

    beta = if is_nil(openai.beta), do: [], else: [{"OpenAI-Beta", openai.beta}]
    base ++ org ++ beta
  end

  @doc false
  def post(openai = %OpenaiEx{}, url) do
    Req.new(
      method: :post,
      url: openai.base_url <> url,
      headers: headers(openai)
    )
    |> request!()
  end

  @doc false
  def post(openai = %OpenaiEx{}, url, multipart: multipart) do
    Req.new(
      method: :post,
      url: openai.base_url <> url,
      headers:
        headers(openai) ++
          [
            {"Content-Type", Multipart.content_type(multipart, "multipart/form-data")},
            {"Content-Length", to_string(Multipart.content_length(multipart))}
          ],
      body: Multipart.body_stream(multipart)
    )
    |> request!()
  end

  @doc false
  def post(openai = %OpenaiEx{}, url, json: json) do
    Req.new(
      method: :post,
      url: openai.base_url <> url,
      headers:
        headers(openai) ++
          [{"Content-Type", "application/json"}, {"Accept", "application/json"}],
      json: json
    )
    |> request!()
  end

  def post_no_decode(openai = %OpenaiEx{}, url, json: json) do
    Req.new(
      method: :post,
      url: openai.base_url <> url,
      headers: headers(openai) ++ [{"Content-Type", "application/json"}],
      json: json
    )
    |> request!()
  end

  @doc false
  def get(openai = %OpenaiEx{}, base_url, params) do
    query =
      base_url
      |> URI.new!()
      |> URI.append_query(params |> URI.encode_query())
      |> URI.to_string()

    openai |> get(query)
  end

  @doc false
  def get(openai = %OpenaiEx{}, url) do
    Req.new(
      method: :get,
      url: openai.base_url <> url,
      headers: headers(openai) ++ [{"Accept", "application/json"}]
    )
    |> request!()
  end

  def get_no_decode(openai = %OpenaiEx{}, url) do
    Req.new(
      method: :get,
      url: openai.base_url <> url,
      headers: headers(openai)
    )
    |> request!()
  end

  @doc false
  def delete(openai = %OpenaiEx{}, url) do
    Req.new(
      method: :delete,
      url: openai.base_url <> url,
      headers: headers(openai) ++ [{"Accept", "application/json"}]
    )
    |> request!()
  end

  defp request!(req, try_count \\ 1) do
    try do
      req
      |> Req.update(
        finch: OpenaiEx.Finch,
        receive_timeout: get_receive_timeout(),
        retry: :transient,
        retry_log_level: :info
      )
      |> Req.request!()
      |> Map.get(:body)
    rescue
      e ->
        case try_count < get_max_try_count() do
          true ->
            Logger.warning("OpenaiEX retrying request (try #{try_count}): #{inspect(e)}")
            Process.sleep(:timer.seconds(1))
            request!(req, try_count + 1)

          false ->
            raise e
        end
    end
  end

  @default_receive_timeout :timer.minutes(2)
  defp get_receive_timeout() do
    Application.get_env(:openai_ex, :http, [])
    |> Keyword.get(:receive_timeout, @default_receive_timeout)
  end

  @default_max_try_count 2
  defp get_max_try_count() do
    Application.get_env(:openai_ex, :http, [])
    |> Keyword.get(:max_try_count, @default_max_try_count)
  end

  @doc false
  def to_multi_part_form_data(req, file_fields) do
    mp =
      req
      |> Map.drop(file_fields)
      |> Enum.reduce(Multipart.new(), fn {k, v}, acc ->
        acc |> Multipart.add_part(Multipart.Part.text_field(v, k))
      end)

    req
    |> Map.take(file_fields)
    |> Enum.reduce(mp, fn {k, v}, acc ->
      acc |> Multipart.add_part(to_file_field_part(k, v))
    end)
  end

  @doc false
  defp to_file_field_part(k, v) do
    case v do
      {path} ->
        Multipart.Part.file_field(path, k)

      {filename, content} ->
        Multipart.Part.file_content_field(filename, content, k, filename: filename)

      content ->
        Multipart.Part.file_content_field("", content, k, filename: "")
    end
  end
end
