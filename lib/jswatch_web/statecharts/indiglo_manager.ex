defmodule JswatchWeb.IndigloManager do
  @moduledoc """
  Gestiona la luz de fondo (Indiglo). Ahora es iniciado por el supervisor
  y maneja los eventos de forma robusta.
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
    # No se usa gproc aquí, ya que la comunicación es más explícita ahora.
    {:ok, %{ui_pid: nil, st: :off, turn_off_timer: nil}}
  end

  # --- Manejadores de Cast ---

  # CAMBIO: commit -> "Registra la UI activa para recibir eventos."
  def handle_cast({:register_ui, ui_pid}, state) do
    {:noreply, %{state | ui_pid: ui_pid}}
  end

  # CAMBIO: commit -> "Maneja el evento de presionar el botón superior derecho."
  def handle_cast({:button_press, :top_right}, %{ui_pid: ui_pid, st: st} = state) do
    # Si hay un temporizador para apagar la luz, lo cancelamos.
    if timer = state.turn_off_timer, do: Process.cancel_timer(timer)

    # Encendemos la luz.
    if ui_pid, do: GenServer.cast(ui_pid, :set_indiglo)

    # Programamos que la luz se apague sola después de 3 segundos.
    new_timer = Process.send_after(self(), :turn_off_indiglo, 3000)

    # Actualizamos el estado.
    {:noreply, %{state | st: :on, turn_off_timer: new_timer}}
  end

  # Manejador para cualquier otro cast (lo ignoramos).
  def handle_cast(_msg, state), do: {:noreply, state}


  # --- Manejadores de Info (Timers) ---

  # CAMBIO: commit -> "Maneja el evento de apagar la luz después del temporizador."
  def handle_info(:turn_off_indiglo, %{ui_pid: ui_pid} = state) do
    if ui_pid, do: GenServer.cast(ui_pid, :unset_indiglo)
    {:noreply, %{state | st: :off, turn_off_timer: nil}}
  end

  # Manejador para cualquier otra info (la ignoramos).
  def handle_info(_event, state) do
    {:noreply, state}
  end
end
