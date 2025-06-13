defmodule JswatchWeb.StopwatchManager do
  @moduledoc """
  Gestiona la lógica del cronómetro. Adaptado para ser iniciado por el
  supervisor de la aplicación.
  """
  use GenServer

  # --- API Pública ---

  # CAMBIO: commit -> "Inicia el GenServer con las opciones del supervisor."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  # --- Callbacks del GenServer ---

  # CAMBIO: commit -> "Inicializa el estado sin UI registrada."
  def init(_opts) do
    {:ok, %{ui_pid: nil, count: ~T[00:00:00.00]}}
  end

  # --- Manejadores de Cast ---

  # CAMBIO: commit -> "Registra la UI activa para recibir eventos."
  def handle_cast({:register_ui, ui_pid}, state) do
    {:noreply, %{state | ui_pid: ui_pid}}
  end

  # NOTA: Aquí iría la lógica para los botones del cronómetro.
  # Por ahora, simplemente los aceptamos para que no den error.
  def handle_cast({:button_press, _button}, state) do
    IO.puts("Stopwatch received button press. Logic not implemented yet.")
    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # --- Manejadores de Info ---

  def handle_info(_event, state), do: {:noreply, state}
end
