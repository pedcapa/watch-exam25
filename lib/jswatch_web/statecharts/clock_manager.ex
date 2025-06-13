defmodule JswatchWeb.ClockManager do
  @moduledoc """
  GenServer que gestiona la lógica de un reloj digital de forma robusta.
  Iniciado y supervisado por la aplicación principal.
  """
  use GenServer

  # --- API Pública ---

  # NUEVO: La función start_link ahora acepta 'opts' (opciones).
  # Esto es para que pueda ser iniciado correctamente por el supervisor de la aplicación,
  # que le pasará un nombre (ej. name: ClockManager).
  def start_link(opts) do
    # Inicia el proceso GenServer, pasándole el nombre que recibió de las opciones.
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  # --- Funciones Auxiliares ---
  # Esta función no cambió, pero es parte del código final.
  def format_date(date, show, selection) do
    day = if date.day < 10, do: "0#{date.day}", else: "#{date.day}"
    month = ~w[ENE FEB MAR ABR MAY JUN JUL AGO SEP OCT NOV DIC] |> Enum.at(date.month - 1)
    year = date.year - 2000
    {day, month, year} =
      case selection do
        :day -> {(if show, do: day, else: "  "), month, year}
        :month -> {day, (if show, do: month, else: "   "), year}
        :year -> {day, month, (if show, do: year, else: "  ")}
      end
    "#{day}/#{month}/#{year}"
  end

  # --- Callbacks del GenServer ---

  # CAMBIO: La función init ya no recibe 'ui', sino las opciones del supervisor.
  # El GenServer ahora se inicia "a ciegas", sin saber quién es la UI.
  def init(_opts) do
    # La lógica para obtener la hora y fecha inicial no ha cambiado.
    {_, now} = :calendar.local_time()
    date = Date.utc_today()
    time = Time.from_erl!(now)
    alarm = Time.add(time, 10)
    # CAMBIO: El nombre del mensaje del temporizador es más descriptivo.
    main_timer_ref = Process.send_after(self(), :tick_clock, 1000)
    # CAMBIO: El estado inicial ahora contiene nuevos campos para la lógica de estados.
    {:ok,
     %{
       ui_pid: nil,             # NUEVO: El PID de la UI se inicia como nulo. Se establecerá más tarde.
       time: time,
       date: date,
       alarm: alarm,
       st1: :working,           # NUEVO: Estado del reloj (:working o :stopped).
       st2: :idle,              # NUEVO: Estado de edición (:idle o :editing).
       selection: :day,         # NUEVO: Parte de la fecha seleccionada para editar.
       show: true,              # NUEVO: Controla el parpadeo del valor seleccionado.
       count: 0,                # NUEVO: Contador para el timeout de inactividad en edición.
       main_timer: main_timer_ref, # NUEVO: Guarda la referencia del temporizador principal.
       edit_timer: nil            # NUEVO: Guardará la referencia del temporizador de edición.
     }}
  end

  # --- Manejadores de Eventos (Cast) ---

  # NUEVO: Esta función maneja el mensaje que envía el canal cuando un usuario se conecta.
  def handle_cast({:register_ui, ui_pid}, state) do
    # Guarda el PID del canal en el estado, para saber a quién enviar las actualizaciones.
    {:noreply, %{state | ui_pid: ui_pid}}
  end

  # NUEVO: Esta función maneja el mensaje del canal para que el reloj reenvíe su estado actual.
  # Es útil para que cuando un usuario se conecte, la pantalla se actualice inmediatamente.
  def handle_cast(:resend_display, %{ui_pid: ui_pid, time: time, date: date} = state) do
    # Si ya tenemos una UI registrada...
    if ui_pid do
      # ...le enviamos la hora y la fecha actual.
      GenServer.cast(ui_pid, {:set_time_display, Time.truncate(time, :second) |> Time.to_string()})
      GenServer.cast(ui_pid, {:set_date_display, format_date(date, true, :day)})
    end
    # Devuelve el estado sin cambios.
    {:noreply, state}
  end

  # NUEVO: Maneja el botón 'bottom_right' solo cuando estamos en modo reposo (:idle).
  def handle_cast({:button_press, :bottom_right}, %{st2: :idle, ui_pid: ui_pid} = state) do
    # Si el temporizador principal está activo, lo cancela para detener el tiempo.
    if timer_ref = state.main_timer, do: Process.cancel_timer(timer_ref)
    # Inicia el temporizador de edición (para el parpadeo y timeout).
    edit_timer_ref = Process.send_after(self(), :tick_edit, 250)
    # Actualiza la UI para que la parte seleccionada (el día) "desaparezca" (inicio del parpadeo).
    if ui_pid, do: GenServer.cast(ui_pid, {:set_date_display, format_date(state.date, false, :day)})
    # Actualiza el estado del GenServer para reflejar la entrada al modo de edición.
    new_state =
      state
      |> Map.put(:st1, :stopped)     # Cambia el estado del reloj a detenido.
      |> Map.put(:st2, :editing)     # Cambia el estado de edición a editando.
      |> Map.put(:selection, :day)   # Establece el día como la selección inicial.
      |> Map.put(:count, 0)          # Reinicia el contador de inactividad.
      |> Map.put(:show, false)       # Pone 'show' en falso para que parpadee.
      |> Map.put(:main_timer, nil)   # Limpia la referencia del temporizador principal.
      |> Map.put(:edit_timer, edit_timer_ref) # Guarda la nueva referencia del temporizador de edición.
    {:noreply, new_state}
  end

  # NUEVO: Maneja el botón 'bottom_right' solo cuando ya estamos editando.
  def handle_cast({:button_press, :bottom_right}, %{st2: :editing, ui_pid: ui_pid} = state) do
    # Si hay un temporizador de edición, lo cancela. Esto resetea el contador de inactividad.
    if timer_ref = state.edit_timer, do: Process.cancel_timer(timer_ref)
    # Calcula la nueva fecha dependiendo de la parte que esté seleccionada.
    new_date =
      case state.selection do
        # Si es el día, simplemente suma 1 día.
        :day ->
          Date.add(state.date, 1)
        # CAMBIO: Lógica robusta para sumar meses, que antes tenía un error.
        :month ->
          # Convierte la fecha a una tupla de Erlang {año, mes, día}.
          {y, m, d} = Date.to_erl(state.date)
          # Suma un mes.
          new_m = m + 1
          # Si el nuevo mes es > 12, pasa al siguiente año y mes 1.
          {final_y, final_m} = if new_m > 12, do: {y + 1, 1}, else: {y, new_m}
          # Obtiene el último día válido del nuevo mes (ej. 28, 29, 30 o 31).
          last_day = :calendar.last_day_of_the_month(final_y, final_m)
          # El nuevo día es el menor entre el día original y el último día válido.
          final_d = min(d, last_day)
          # Crea la nueva fecha a partir de la tupla.
          {:ok, d} = Date.from_erl({final_y, final_m, final_d})
          d
        # CAMBIO: Lógica robusta para sumar años, manejando años bisiestos.
        :year ->
          {y, m, d} = Date.to_erl(state.date)
          new_y = y + 1
          # Si era un 29 de febrero y el nuevo año no es bisiesto, el día se ajustará a 28.
          last_day = :calendar.last_day_of_the_month(new_y, m)
          final_d = min(d, last_day)
          {:ok, d} = Date.from_erl({new_y, m, final_d})
          d
      end
    # Muestra la nueva fecha en la UI.
    if ui_pid, do: GenServer.cast(ui_pid, {:set_date_display, format_date(new_date, true, state.selection)})
    # Inicia un nuevo temporizador de edición para continuar con el parpadeo/timeout.
    edit_timer_ref = Process.send_after(self(), :tick_edit, 250)
    # Actualiza el estado con la nueva fecha.
    new_state =
      state
      |> Map.put(:date, new_date)
      |> Map.put(:show, true) # Asegura que el valor sea visible.
      |> Map.put(:count, 0)
      |> Map.put(:edit_timer, edit_timer_ref)
    {:noreply, new_state}
  end

  # NUEVO: Maneja el botón 'bottom_left' solo cuando estamos editando.
  def handle_cast({:button_press, :bottom_left}, %{st2: :editing, ui_pid: ui_pid} = state) do
    # Cancela y resetea el temporizador de inactividad.
    if timer_ref = state.edit_timer, do: Process.cancel_timer(timer_ref)
    # Cicla la selección: día -> mes -> año -> día.
    new_selection =
      case state.selection do
        :day -> :month
        :month -> :year
        :year -> :day
      end
    # Muestra la fecha con la nueva selección visible.
    if ui_pid, do: GenServer.cast(ui_pid, {:set_date_display, format_date(state.date, true, new_selection)})
    # Inicia un nuevo temporizador de edición.
    edit_timer_ref = Process.send_after(self(), :tick_edit, 250)
    # Actualiza el estado con la nueva selección.
    new_state =
      state
      |> Map.put(:selection, new_selection)
      |> Map.put(:show, true)
      |> Map.put(:count, 0)
      |> Map.put(:edit_timer, edit_timer_ref)
    {:noreply, new_state}
  end

  # NUEVO: Cláusula para ignorar cualquier otro mensaje `cast` que no coincida.
  def handle_cast(_msg, state), do: {:noreply, state}

  # --- Manejadores de Información (Timers) ---

  # CAMBIO: El antiguo :working_working ahora es :tick_clock y comprueba la UI.
  def handle_info(:tick_clock, %{st1: :working, ui_pid: ui_pid, time: time, alarm: alarm} = state) do
    time = Time.add(time, 1)
    if time == alarm, do: :gproc.send({:p, :l, :ui_event}, :start_alarm)
    # Si hay una UI registrada, le envía la actualización de la hora.
    if ui_pid, do: GenServer.cast(ui_pid, {:set_time_display, Time.truncate(time, :second) |> Time.to_string()})
    # Programa el siguiente tick y guarda la nueva referencia del temporizador.
    main_timer_ref = Process.send_after(self(), :tick_clock, 1000)
    # Actualiza el estado con la nueva hora y la nueva referencia del temporizador.
    {:noreply, state |> Map.put(:time, time) |> Map.put(:main_timer, main_timer_ref)}
  end

  # NUEVO: Maneja el temporizador de edición.
  def handle_info(:tick_edit, %{st2: :editing, count: count, ui_pid: ui_pid} = state) do
    # Si el contador de inactividad es menor a 20 (5 segundos)...
    if count < 20 do
      # ...continúa el parpadeo.
      new_show = !state.show # Invierte el estado de visibilidad.
      if ui_pid, do: GenServer.cast(ui_pid, {:set_date_display, format_date(state.date, new_show, state.selection)})
      edit_timer_ref = Process.send_after(self(), :tick_edit, 250) # Programa el siguiente parpadeo.
      new_state =
        state
        |> Map.put(:show, new_show)
        |> Map.put(:count, count + 1) # Incrementa el contador.
        |> Map.put(:edit_timer, edit_timer_ref)
      {:noreply, new_state}
    else
      # Si el contador llega a 20, el tiempo de espera ha finalizado. Sal del modo edición.
      if ui_pid, do: GenServer.cast(ui_pid, {:set_date_display, format_date(state.date, true, state.selection)})
      # Reanuda el reloj principal.
      main_timer_ref = Process.send_after(self(), :tick_clock, 1000)
      # Regresa al estado inicial.
      new_state =
        state
        |> Map.put(:st1, :working) # Reanuda el reloj.
        |> Map.put(:st2, :idle)    # Vuelve al modo reposo.
        |> Map.put(:show, true)
        |> Map.put(:count, 0)
        |> Map.put(:main_timer, main_timer_ref) # Guarda la nueva referencia del temporizador.
        |> Map.put(:edit_timer, nil) # Limpia la referencia del temporizador de edición.
      {:noreply, new_state}
    end
  end

  # CAMBIO: Esta función ahora solo ignora los mensajes de temporizador que no coincidan.
  # El antiguo `handle_info` para botones ahora es `handle_cast`.
  def handle_info(_event, state), do: {:noreply, state}
end
