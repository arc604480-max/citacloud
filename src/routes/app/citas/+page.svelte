<script lang="ts">
  import { CalendarDays, CalendarPlus, Clock3, Stethoscope, CheckCircle, AlertCircle, XCircle } from 'lucide-svelte';
  import { dateTime, dateOnly, dateShort, timeOnly, dateKey, statusLabel } from '$lib/format';

  let { data, form } = $props();

  const todayLima = dateKey(new Date());

  // Filtros principales
  let specialty = $state('all');
  let doctor = $state('all');
  let selectedDate = $state(todayLima);
  let selectedSlotId = $state<string | null>(null);

  // Médicos filtrados por especialidad
  let filteredDoctors = $derived(
    data.doctors.filter((d: any) => specialty === 'all' || String(d.specialty?.id) === specialty)
  );

  // Fechas que tienen disponibilidad para el médico y especialidad seleccionados
  let availableDates = $derived.by(() => {
    const dates = new Set<string>();
    for (const s of data.slots) {
      const matchDoc = doctor === 'all' || s.doctor_id === doctor;
      const matchSpec = specialty === 'all' || filteredDoctors.some((d: any) => d.id === s.doctor_id);
      if (matchDoc && matchSpec) {
        dates.add(dateKey(s.starts_at));
      }
    }
    return Array.from(dates).sort();
  });

  // Turnos para el médico y fecha elegida
  let daySlots = $derived(
    data.slots.filter((s: any) => {
      const matchDoc = doctor === 'all' || s.doctor_id === doctor;
      const matchSpec = specialty === 'all' || filteredDoctors.some((d: any) => d.id === s.doctor_id);
      const matchDay = !selectedDate || dateKey(s.starts_at) === selectedDate;
      return matchDoc && matchSpec && matchDay;
    })
  );

  // Turno seleccionado actualmente
  let selectedSlot = $derived(data.slots.find((s: any) => s.id === selectedSlotId));
  let selectedSlotDoctor = $derived(
    selectedSlot ? data.doctors.find((d: any) => d.id === selectedSlot.doctor_id) : null
  );

  function selectDoctor(docId: string) {
    doctor = docId;
    selectedSlotId = null;
    // Si la fecha actual no está disponible, seleccionar la primera con disponibilidad
    if (availableDates.length > 0 && !availableDates.includes(selectedDate)) {
      selectedDate = availableDates[0];
    }
  }

  function pickDate(d: string) {
    selectedDate = d;
    selectedSlotId = null;
  }
</script>

<svelte:head>
  <title>Citas médicas · CitaCloud</title>
</svelte:head>

<div class="heading">
  <span class="eyebrow">CITAS MÉDICAS</span>
  <h1>Tu atención médica, a tu ritmo</h1>
  <p class="muted">
    Elige médico y fecha en el calendario. Consulta las horas concretas disponibles de 30 minutos y confirma tu reserva al instante.
  </p>
</div>

{#if form?.message}
  <div class="alert"><AlertCircle size={18} /> {form.message}</div>
{/if}
{#if form?.success}
  <div class="alert success"><CheckCircle size={18} /> {form.success}</div>
{/if}

<!-- Sección de Reserva del Paciente -->
<section class="card booking-card">
  <div class="booking-header">
    <div class="header-icon"><CalendarPlus size={22} /></div>
    <div>
      <h2>Reservar cita médica</h2>
      <p class="muted small">Disponibilidad en tiempo real. Al reservar una hora, solo ese turno se ocupa.</p>
    </div>
  </div>

  <!-- Paso 1: Filtros de Especialidad y Médico -->
  <div class="filters-row">
    <div class="filter-col">
      <label for="specialty-filter">1. Especialidad</label>
      <select
        id="specialty-filter"
        bind:value={specialty}
        onchange={() => { doctor = 'all'; selectedSlotId = null; }}
      >
        <option value="all">Todas las especialidades</option>
        {#each data.specialties as sp}
          <option value={String(sp.id)}>{sp.name}</option>
        {/each}
      </select>
    </div>

    <div class="filter-col">
      <label for="doctor-filter">2. Médico</label>
      <select
        id="doctor-filter"
        bind:value={doctor}
        onchange={(e) => selectDoctor((e.target as HTMLSelectElement).value)}
      >
        <option value="all">Todos los médicos</option>
        {#each filteredDoctors as d}
          <option value={d.id}>{d.profile?.full_name} ({d.specialty?.name})</option>
        {/each}
      </select>
    </div>

    <div class="filter-col">
      <label for="date-picker">3. Fecha de consulta</label>
      <input
        class="input"
        id="date-picker"
        type="date"
        bind:value={selectedDate}
        min={todayLima}
        onchange={() => { selectedSlotId = null; }}
      />
    </div>
  </div>

  <!-- Barra de días disponibles (calendario rápido) -->
  {#if availableDates.length > 0}
    <div class="dates-strip">
      <span class="strip-label"><CalendarDays size={15} /> Fechas con disponibilidad:</span>
      <div class="date-chips">
        {#each availableDates as d}
          <button
            type="button"
            class="date-chip"
            class:active={selectedDate === d}
            onclick={() => pickDate(d)}
          >
            <strong>{dateShort(`${d}T12:00:00-05:00`)}</strong>
            <small>{d}</small>
          </button>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Paso 2: Selección de Hora Concreta (Turnos de 30 minutos) -->
  <div class="slots-container">
    <div class="slots-header">
      <h3>
        <Clock3 size={18} />
        Horas disponibles para el {selectedDate ? dateOnly(`${selectedDate}T12:00:00-05:00`) : 'día seleccionado'}
      </h3>
      <span class="pill-count">{daySlots.length} turno{daySlots.length === 1 ? '' : 's'} de 30m</span>
    </div>

    {#if daySlots.length > 0}
      <div class="slots-grid">
        {#each daySlots as s}
          {@const doc = data.doctors.find((d: any) => d.id === s.doctor_id)}
          <button
            type="button"
            class="slot-btn"
            class:selected={selectedSlotId === s.id}
            onclick={() => selectedSlotId = s.id}
          >
            <span class="slot-time">{timeOnly(s.starts_at)}</span>
            <span class="slot-end">hasta {timeOnly(s.ends_at)}</span>
            {#if doctor === 'all'}
              <span class="slot-doc">{doc?.profile?.full_name}</span>
            {/if}
          </button>
        {/each}
      </div>
    {:else}
      <div class="empty-slots">
        <p>No hay turnos disponibles para los filtros seleccionados.</p>
        <small class="muted">
          Si eres el administrador o médico, asegúrate de haber configurado una jornada para esta fecha en el panel de agenda.
        </small>
      </div>
    {/if}
  </div>

  <!-- Paso 3: Confirmación de Reserva del Turno Seleccionado -->
  {#if selectedSlot && selectedSlotDoctor}
    <div class="confirm-box">
      <div class="confirm-details">
        <span class="confirm-tag">TURNO SELECCIONADO</span>
        <h4>Consulta con {selectedSlotDoctor.profile?.full_name}</h4>
        <div class="confirm-meta">
          <span><Stethoscope size={15} /> {selectedSlotDoctor.specialty?.name}</span>
          <span><CalendarDays size={15} /> {dateOnly(selectedSlot.starts_at)}</span>
          <span class="highlight-time"><Clock3 size={15} /> {timeOnly(selectedSlot.starts_at)} – {timeOnly(selectedSlot.ends_at)}</span>
        </div>
      </div>
      <div class="confirm-action">
        <form method="POST" action="?/book">
          <input type="hidden" name="slot_id" value={selectedSlot.id} />
          <button class="btn" type="submit">
            Confirmar reserva
          </button>
        </form>
        <button type="button" class="btn text small" onclick={() => selectedSlotId = null}>
          Cambiar hora
        </button>
      </div>
    </div>
  {/if}
</section>

<!-- Historial de Citas del Paciente -->
<section class="card history-card">
  <h2>Mis citas registradas</h2>
  <p class="muted small">Historial de tus atenciones médicas y estado actual.</p>

  {#if data.appointments.length}
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Especialidad y Médico</th>
            <th>Fecha y Turno</th>
            <th>Estado</th>
            <th>Acción</th>
          </tr>
        </thead>
        <tbody>
          {#each data.appointments as a}
            <tr>
              <td>
                <strong>{a.slot?.doctor?.specialty?.name ?? 'Consulta médica'}</strong>
                <small class="muted block">{a.slot?.doctor?.profile?.full_name}</small>
              </td>
              <td>
                {#if a.slot}
                  <strong>{dateOnly(a.slot.starts_at)}</strong>
                  <small class="muted block">{timeOnly(a.slot.starts_at)} (hora local Perú)</small>
                {:else}
                  —
                {/if}
              </td>
              <td>
                <span class="pill" class:cancelled={a.status === 'cancelled'} class:completed={a.status === 'completed'}>
                  {statusLabel(a.status)}
                </span>
              </td>
              <td>
                {#if a.status === 'confirmed' && a.slot && new Date(a.slot.starts_at) > new Date()}
                  <form method="POST" action="?/cancel" onsubmit={(e) => { if (!confirm('¿Estás seguro de cancelar esta cita?')) e.preventDefault(); }}>
                    <input type="hidden" name="appointment_id" value={a.id} />
                    <button class="btn danger small" type="submit">Cancelar cita</button>
                  </form>
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="empty">Aún no has reservado citas. Selecciona un horario arriba para agendar tu primera consulta.</div>
  {/if}
</section>

<style>
  h1 { font-size: 2.2rem; margin: 7px 0; }
  .card { margin-top: 24px; }
  .booking-card { border-top: 4px solid #287562; }
  .booking-header { display: flex; align-items: center; gap: 14px; margin-bottom: 20px; }
  .header-icon {
    display: grid; place-items: center; width: 42px; height: 42px;
    background: #eaf5ee; color: #287562; border-radius: 10px; flex-shrink: 0;
  }
  .filters-row {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 18px;
  }
  .filter-col { display: flex; flex-direction: column; gap: 6px; }
  .filter-col label { font-size: 0.85rem; font-weight: 700; color: #2f4945; }

  .dates-strip {
    background: #f7fbf9; border: 1px solid #e1eee8; border-radius: 10px;
    padding: 12px 14px; margin-bottom: 20px;
  }
  .strip-label {
    display: flex; align-items: center; gap: 6px; font-size: 0.82rem;
    font-weight: 700; color: #24574d; margin-bottom: 10px;
  }
  .date-chips {
    display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px;
  }
  .date-chip {
    flex: none; border: 1px solid #cedcd6; background: #fff; padding: 8px 12px;
    border-radius: 8px; cursor: pointer; text-align: center; transition: all 0.15s;
  }
  .date-chip strong { display: block; font-size: 0.84rem; color: #1e3a37; }
  .date-chip small { font-size: 0.72rem; color: #6e8480; }
  .date-chip:hover { border-color: #287562; background: #eaf5ee; }
  .date-chip.active {
    background: #287562; border-color: #287562; color: #fff;
  }
  .date-chip.active strong, .date-chip.active small { color: #fff; }

  .slots-container {
    background: #fff; border: 1px solid #e2ece7; border-radius: 12px; padding: 18px; margin-bottom: 20px;
  }
  .slots-header {
    display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;
  }
  .slots-header h3 {
    display: flex; align-items: center; gap: 8px; font-size: 1.05rem; margin: 0; color: #1d3c39;
  }
  .pill-count {
    background: #eaf5ee; color: #287562; padding: 4px 10px; border-radius: 20px;
    font-size: 0.78rem; font-weight: 700;
  }
  .slots-grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 10px;
  }
  .slot-btn {
    border: 1px solid #d3e4dc; background: #fbfdfc; padding: 10px 8px;
    border-radius: 9px; cursor: pointer; text-align: center; transition: all 0.15s;
    display: flex; flex-direction: column; align-items: center;
  }
  .slot-btn:hover { border-color: #287562; background: #f0f8f4; transform: translateY(-1px); }
  .slot-btn.selected {
    background: #287562; border-color: #287562; color: #fff;
    box-shadow: 0 4px 10px rgba(40,117,98,0.25);
  }
  .slot-time { font-size: 1.05rem; font-weight: 800; color: #1c4b42; }
  .slot-btn.selected .slot-time { color: #fff; }
  .slot-end { font-size: 0.72rem; color: #6b847f; margin-top: 2px; }
  .slot-btn.selected .slot-end { color: #d6eee4; }
  .slot-doc {
    font-size: 0.7rem; color: #287562; margin-top: 4px; font-weight: 600;
    max-width: 100%; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .slot-btn.selected .slot-doc { color: #fff; }

  .empty-slots { text-align: center; padding: 30px 10px; color: #58716c; }
  .empty-slots p { font-size: 0.95rem; font-weight: 700; margin: 0 0 6px 0; }

  .confirm-box {
    background: #eaf5ee; border: 2px solid #287562; border-radius: 12px;
    padding: 18px 22px; display: flex; justify-content: space-between; align-items: center;
    gap: 16px; margin-top: 10px;
  }
  .confirm-tag {
    font-size: 0.68rem; font-weight: 800; letter-spacing: 0.08em;
    color: #287562; background: #fff; padding: 3px 8px; border-radius: 4px;
  }
  .confirm-details h4 { margin: 6px 0 8px 0; font-size: 1.15rem; color: #163e37; }
  .confirm-meta { display: flex; flex-wrap: wrap; gap: 14px; font-size: 0.85rem; color: #355e56; }
  .confirm-meta span { display: inline-flex; align-items: center; gap: 5px; }
  .highlight-time { font-weight: 800; color: #163e37; }
  .confirm-action { display: flex; flex-direction: column; align-items: flex-end; gap: 8px; }

  .block { display: block; }
  .history-card h2 { font-size: 1.25rem; margin-bottom: 4px; }

  @media (max-width: 850px) {
    .filters-row { grid-template-columns: 1fr; }
    .confirm-box { flex-direction: column; align-items: flex-start; }
    .confirm-action { width: 100%; align-items: stretch; }
    .confirm-action .btn { width: 100%; }
  }
</style>
