defmodule JswatchWeb.WatchUIChannel do
  use Phoenix.Channel
  alias JswatchWeb.{ClockManager, IndigloManager, StopwatchManager}

  def join("watch:ui", _message, socket) do
    # Registra este canal como la UI activa para los managers
    GenServer.cast(ClockManager, {:register_ui, self()})
    GenServer.cast(IndigloManager, {:register_ui, self()})
    GenServer.cast(StopwatchManager, {:register_ui, self()})

    # Pide al ClockManager que envíe su estado actual para pintar la UI inicial
    GenServer.cast(ClockManager, :resend_display)

    {:ok, socket}
  end

  # CAMBIO: commit -> "Manejador de eventos de botones."
  # Ignoramos los eventos "-released" por ahora, ya que la lógica se basa en el "-pressed".
  def handle_in(event, _payload, socket) do
    case event do
      "bottom-right-pressed" ->
        GenServer.cast(ClockManager, {:button_press, :bottom_right})
        # GenServer.cast(StopwatchManager, {:button_press, :bottom_right})

      "bottom-left-pressed" ->
        GenServer.cast(ClockManager, {:button_press, :bottom_left})
        # GenServer.cast(StopwatchManager, {:button_press, :bottom_left})

      "top-right-pressed" ->
        GenServer.cast(IndigloManager, {:button_press, :top_right})

      _ ->
        # Ignora otros eventos como "top-right-released", etc.
        :ok
    end

    {:noreply, socket}
  end

  def handle_cast({:set_time_display, str}, socket) do
    push(socket, "setTimeDisplay", %{time: str})
    {:noreply, socket}
  end

  def handle_cast({:set_date_display, str}, socket) do
    push(socket, "setDateDisplay", %{date: str})
    {:noreply, socket}
  end

  def handle_cast(:set_indiglo, socket) do
    push(socket, "setIndiglo", %{})
    {:noreply, socket}
  end

  def handle_cast(:unset_indiglo, socket) do
    push(socket, "unsetIndiglo", %{})
    {:noreply, socket}
  end
end
