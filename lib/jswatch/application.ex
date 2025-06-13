defmodule Jswatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias JswatchWeb.{ClockManager, IndigloManager, StopwatchManager}

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      JswatchWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Jswatch.PubSub},
      # Start Finch
      {Finch, name: Jswatch.Finch},
      # Start the Endpoint (http/https)
      JswatchWeb.Endpoint,

      # CAMBIOS: commit -> "Cambios en la lógica de los GenServers para que sean iniciados application.ex"
      # Inicia los GenServers de la lógica del reloj como workers supervisados.
      # Se inician una sola vez con la aplicación.
      {ClockManager, name: ClockManager},
      {IndigloManager, name: IndigloManager},
      {StopwatchManager, name: StopwatchManager}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jswatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JswatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
