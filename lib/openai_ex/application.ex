defmodule OpenaiEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    finch_opts =
      Application.get_env(:openai_ex, :http, [])
      |> Keyword.get(:finch_opts, [])
      |> Keyword.merge(name: OpenaiEx.Finch)

    children = [
      {Finch, finch_opts}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
