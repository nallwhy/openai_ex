defmodule OpenaiEx.Http do
  @moduledoc false

  @doc false
  def headers(openai = %OpenaiEx{}) do
    base = [{"Authorization", "Bearer #{openai.token}"}]

    org =
      if is_nil(openai.organization), do: [], else: [{"OpenAI-Organization", openai.organization}]

    beta = if is_nil(openai.beta), do: [], else: [{"OpenAI-Beta", openai.beta}]
    base ++ org ++ beta
  end

  defp opts(opts) do
    [
      finch: OpenaiEx.Finch,
      receive_timeout: 120_000
    ]
    |> Keyword.merge(opts)
  end

  @doc false
  def post(openai = %OpenaiEx{}, url) do
    Req.post!(
      openai.base_url <> url,
      opts(headers: headers(openai))
    ).body
  end

  @doc false
  def post(openai = %OpenaiEx{}, url, multipart: multipart) do
    Req.post!(
      openai.base_url <> url,
      opts(
        headers:
          headers(openai) ++
            [
              {"Content-Type", Multipart.content_type(multipart, "multipart/form-data")},
              {"Content-Length", to_string(Multipart.content_length(multipart))}
            ],
        body: Multipart.body_stream(multipart)
      )
    ).body
  end

  @doc false
  def post(openai = %OpenaiEx{}, url, json: json) do
    Req.post!(
      openai.base_url <> url,
      opts(
        headers:
          headers(openai) ++
            [{"Content-Type", "application/json"}, {"Accept", "application/json"}],
        json: json
      )
    ).body
  end

  def post_no_decode(openai = %OpenaiEx{}, url, json: json) do
    Req.post!(
      openai.base_url <> url,
      opts(
        headers: headers(openai) ++ [{"Content-Type", "application/json"}],
        json: json
      )
    ).body
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
    Req.get!(
      openai.base_url <> url,
      opts(headers: headers(openai) ++ [{"Accept", "application/json"}])
    ).body
  end

  def get_no_decode(openai = %OpenaiEx{}, url) do
    Req.get!(
      openai.base_url <> url,
      opts(headers: headers(openai))
    ).body
  end

  @doc false
  def delete(openai = %OpenaiEx{}, url) do
    Req.delete!(
      openai.base_url <> url,
      opts(headers: headers(openai) ++ [{"Accept", "application/json"}])
    ).body
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
