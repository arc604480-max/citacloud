<script lang="ts">
  import { dateTime, dateOnly, timeOnly, dateKey, statusLabel, shiftTypeLabel } from '$lib/format';
  import { CalendarDays, Clock3, Coffee, Stethoscope, CheckCircle, Edit3, Trash2, PlusCircle, AlertCircle } from 'lucide-svelte';

  let { data, form } = $props();

  // Helper para obtener hoy en formato YYYY-MM-DD (hora de Lima)
  const todayLima = dateKey(new Date());

  // Form state
  let shiftId = $state<string | null>(null);
  let workDate = $state(todayLima);
  let shiftType = $state<'full_day' | 'half_day' | 'custom'>('full_day');
  let startTime = $state('08:00');
  let endTime = $state('19:00');
  let hasBreak = $state(true);
  let breakStartTime = $state('13:00');
  let breakEndTime = $state('14:00');

  function applyPreset(type: 'full_day' | 'half_day' | 'custom') {
    shiftType = type;
    if (type === 'full_day') {
      startTime = '08:00';
      endTime = '19:00';
      hasBreak = true;
      breakStartTime = '13:00';
      breakEndTime = '14:00';
    } else if (type === 'half_day') {
      startTime = '08:00';
      endTime = '13:00';
      hasBreak = false;
    }
  }

  function editShift(s: any) {
    shiftId = s.id;
    workDate = s.work_date;
    shiftType = s.shift_type;
    startTime = timeOnly(s.starts_at);
    endTime = timeOnly(s.ends_at);
    hasBreak = Boolean(s.break_starts_at && s.break_ends_at);
    if (hasBreak) {
      breakStartTime = timeOnly(s.break_starts_at);
      breakEndTime = timeOnly(s.break_ends_at);
    }
    // Scroll al formulario
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function resetForm() {
    shiftId = null;
    workDate = todayLima;
    applyPreset('full_day');
  }

  // Filtrado de citas/turnos para el visor
  let selectedFilterDate = $state('all');
  let filteredSlots = $derived(
    data.slots.filter((s: any) => selectedFilterDate === 'all' || dateKey(s.starts_at) === selectedFilterDate)
  );
</script>

<svelte:head>
  <title>Agenda médica · CitaCloud</title>
</svelte:head>

<div class="heading">
  <span class="eyebrow">PANEL MÉDICO</span>
  <h1>Agenda y jornadas de atención</h1>
  <p class="muted">
    Configura tus jornadas de disponibilidad por fecha. El sistema generará automáticamente los turnos de 30 minutos para los pacientes.
  </p>
</div>

{#if form?.message}
  <div class="alert"><AlertCircle size={18} /> {form.message}</div>
{/if}
{#if form?.success}
  <div class="alert success"><CheckCircle size={18} /> {form.success}</div>
{/if}

<!-- Formulario de Configuración de Jornada -->
<section class="card config-card">
  <div class="card-header">
    <div class="header-icon"><Stethoscope size={22} /></div>
    <div>
      <h2>{shiftId ? 'Modificar jornada de atención' : 'Configurar nueva jornada de atención'}</h2>
      <p class="muted small">
        Define cuándo estás disponible; el sistema generará automáticamente turnos de 30 minutos excluyendo descansos.
      </p>
    </div>
  </div>

  {#if shiftId}
    <div class="editing-banner">
      <span>Modificando jornada existente.</span>
      <button type="button" class="btn small text" onclick={resetForm}>Cancelar edición</button>
    </div>
  {/if}

  <form method="POST" action="?/save_shift" class="shift-form">
    {#if shiftId}
      <input type="hidden" name="shift_id" value={shiftId} />
    {/if}

    <!-- Selector de modalidad -->
    <div class="form-group full-width">
      <span class="field-label">Modalidad de jornada</span>
      <div class="preset-buttons">
        <button
          type="button"
          class="preset-btn"
          class:active={shiftType === 'full_day'}
          onclick={() => applyPreset('full_day')}
        >
          <strong>Día completo</strong>
          <span>08:00 – 19:00 (con descanso)</span>
        </button>
        <button
          type="button"
          class="preset-btn"
          class:active={shiftType === 'half_day'}
          onclick={() => applyPreset('half_day')}
        >
          <strong>Medio día</strong>
          <span>08:00 – 13:00</span>
        </button>
        <button
          type="button"
          class="preset-btn"
          class:active={shiftType === 'custom'}
          onclick={() => applyPreset('custom')}
        >
          <strong>Personalizado</strong>
          <span>Ajuste libre</span>
        </button>
      </div>
      <input type="hidden" name="shift_type" value={shiftType} />
    </div>

    <!-- Fecha -->
    <div class="form-group">
      <label for="work_date">Fecha de atención</label>
      <input
        class="input"
        id="work_date"
        type="date"
        name="work_date"
        bind:value={workDate}
        min={todayLima}
        required
      />
    </div>

    <!-- Horas de Inicio y Fin -->
    <div class="form-group">
      <label for="start_time">Hora de inicio</label>
      <input class="input" id="start_time" type="time" name="start_time" bind:value={startTime} required />
    </div>

    <div class="form-group">
      <label for="end_time">Hora de fin</label>
      <input class="input" id="end_time" type="time" name="end_time" bind:value={endTime} required />
    </div>

    <!-- Descanso Opcional -->
    <div class="break-section full-width">
      <label class="checkbox-label">
        <input type="checkbox" name="has_break" bind:checked={hasBreak} />
        <span><Coffee size={16} /> Incluir horario de descanso (almuerzo / pausa)</span>
      </label>

      {#if hasBreak}
        <div class="break-inputs">
          <div>
            <label for="break_start_time">Inicio del descanso</label>
            <input
              class="input"
              id="break_start_time"
              type="time"
              name="break_start_time"
              bind:value={breakStartTime}
              required={hasBreak}
            />
          </div>
          <div>
            <label for="break_end_time">Fin del descanso</label>
            <input
              class="input"
              id="break_end_time"
              type="time"
              name="break_end_time"
              bind:value={breakEndTime}
              required={hasBreak}
            />
          </div>
        </div>
      {/if}
    </div>

    <div class="form-actions full-width">
      <button class="btn" type="submit">
        <PlusCircle size={18} /> {shiftId ? 'Guardar cambios de la jornada' : 'Publicar jornada y generar turnos'}
      </button>
    </div>
  </form>
</section>

<!-- Listado de Jornadas Configuradas -->
<section class="card">
  <div class="card-header">
    <div class="header-icon"><CalendarDays size={22} /></div>
    <div>
      <h2>Mis jornadas programadas</h2>
      <p class="muted small">Jornadas creadas para atención médica por fecha.</p>
    </div>
  </div>

  {#if data.shifts.length}
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>Modalidad</th>
            <th>Horario de atención</th>
            <th>Descanso</th>
            <th>Turnos</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          {#each data.shifts as s}
            {@const sSlots = data.slots.filter((slot: any) => slot.shift_id === s.id || (dateKey(slot.starts_at) === s.work_date))}
            {@const bookedCount = sSlots.filter((slot: any) => data.appointments.some((a: any) => a.slot_id === slot.id && a.status === 'confirmed')).length}
            <tr>
              <td>
                <strong>{dateOnly(s.starts_at)}</strong>
                <small class="muted block">{s.work_date}</small>
              </td>
              <td><span class="pill">{shiftTypeLabel(s.shift_type)}</span></td>
              <td><Clock3 size={14} class="inline-icon" /> {timeOnly(s.starts_at)} – {timeOnly(s.ends_at)}</td>
              <td>
                {#if s.break_starts_at && s.break_ends_at}
                  <Coffee size={14} class="inline-icon" /> {timeOnly(s.break_starts_at)} – {timeOnly(s.break_ends_at)}
                {:else}
                  <span class="muted">Sin descanso</span>
                {/if}
              </td>
              <td>
                <span class="turnos-badge">
                  {sSlots.length} turnos de 30m
                  {#if bookedCount > 0}
                    <span class="booked-tag">({bookedCount} reservada{bookedCount > 1 ? 's' : ''})</span>
                  {/if}
                </span>
              </td>
              <td>
                <div class="actions-cell">
                  <button type="button" class="btn secondary small icon-btn" title="Editar jornada" onclick={() => editShift(s)}>
                    <Edit3 size={15} /> Editar
                  </button>
                  <form method="POST" action="?/delete_shift" onsubmit={(e) => { if (!confirm('¿Eliminar esta jornada? Solo es posible si no contiene citas confirmadas.')) e.preventDefault(); }}>
                    <input type="hidden" name="shift_id" value={s.id} />
                    <button type="submit" class="btn danger small icon-btn" title="Eliminar jornada">
                      <Trash2 size={15} />
                    </button>
                  </form>
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="empty">Aún no has configurado ninguna jornada de atención. Utiliza el formulario superior para crear la primera.</div>
  {/if}
</section>

<!-- Visor de Turnos y Citas del Médico -->
<section class="card">
  <div class="card-header space-between">
    <div class="row gap-10">
      <div class="header-icon"><Clock3 size={22} /></div>
      <div>
        <h2>Turnos y pacientes citados</h2>
        <p class="muted small">Revisa el estado de cada intervalo de 30 minutos y completa las consultas atendidas.</p>
      </div>
    </div>
    {#if data.shifts.length}
      <div class="date-filter">
        <label for="filter-date">Filtrar fecha:</label>
        <select id="filter-date" bind:value={selectedFilterDate}>
          <option value="all">Todas las fechas</option>
          {#each data.shifts as s}
            <option value={s.work_date}>{s.work_date} ({dateOnly(s.starts_at)})</option>
          {/each}
        </select>
      </div>
    {/if}
  </div>

  {#if filteredSlots.length}
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Fecha y Turno (30m)</th>
            <th>Paciente</th>
            <th>Estado</th>
            <th>Acción</th>
          </tr>
        </thead>
        <tbody>
          {#each filteredSlots as slot}
            {@const a = data.appointments.find((item: any) => item.slot_id === slot.id)}
            <tr>
              <td>
                <strong>{timeOnly(slot.starts_at)} – {timeOnly(slot.ends_at)}</strong>
                <small class="muted block">{dateOnly(slot.starts_at)}</small>
              </td>
              <td>
                {#if a}
                  <strong>{a.patient?.full_name}</strong>
                {:else}
                  <span class="muted">Libre para reserva</span>
                {/if}
              </td>
              <td>
                {#if a}
                  <span class="pill" class:cancelled={a.status==='cancelled'} class:completed={a.status==='completed'}>
                    {statusLabel(a.status)}
                  </span>
                {:else}
                  <span class="pill free">Disponible</span>
                {/if}
              </td>
              <td>
                {#if a?.status === 'confirmed'}
                  <form method="POST" action="?/complete">
                    <input type="hidden" name="id" value={a.id} />
                    <button class="btn secondary small" type="submit">Completar atención</button>
                  </form>
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="empty">No hay turnos disponibles para la fecha seleccionada.</div>
  {/if}
</section>

<style>
  h1 { font-size: 2.2rem; margin: 7px 0; }
  .card { margin-top: 25px; }
  .card-header { display: flex; align-items: center; gap: 14px; margin-bottom: 20px; }
  .card-header.space-between { justify-content: space-between; flex-wrap: wrap; }
  .header-icon {
    display: grid; place-items: center; width: 42px; height: 42px;
    background: #eaf5ee; color: #287562; border-radius: 10px; flex-shrink: 0;
  }
  .card-header h2 { font-size: 1.25rem; margin: 0 0 3px 0; }
  .editing-banner {
    background: #fff8e6; border: 1px solid #fed888; color: #875a00;
    padding: 10px 14px; border-radius: 8px; margin-bottom: 18px;
    display: flex; justify-content: space-between; align-items: center; font-size: 0.88rem;
  }
  .shift-form {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px;
  }
  .full-width { grid-column: 1 / -1; }
  .form-group { display: flex; flex-direction: column; gap: 6px; }
  .field-label { font-size: 0.85rem; font-weight: 700; color: #364e4b; margin-bottom: 4px; }
  .preset-buttons {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
  }
  .preset-btn {
    border: 1px solid #d5e5df; background: #fff; padding: 12px 14px;
    border-radius: 10px; cursor: pointer; text-align: left; transition: all 0.15s ease;
  }
  .preset-btn strong { display: block; font-size: 0.9rem; color: #1e3e3b; }
  .preset-btn span { display: block; font-size: 0.75rem; color: #768c87; margin-top: 3px; }
  .preset-btn:hover { border-color: #287562; background: #f6fbf8; }
  .preset-btn.active { border-color: #287562; background: #eaf5ee; box-shadow: 0 0 0 2px rgba(40,117,98,0.15); }
  .break-section {
    background: #fbfdfc; border: 1px solid #e7efe9; padding: 16px; border-radius: 10px;
  }
  .checkbox-label {
    display: flex; align-items: center; gap: 8px; font-weight: 600;
    font-size: 0.88rem; color: #284441; cursor: pointer;
  }
  .checkbox-label input { width: 18px; height: 18px; accent-color: #287562; }
  .break-inputs {
    display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 12px;
  }
  .form-actions { display: flex; justify-content: flex-end; margin-top: 8px; }
  :global(.inline-icon) { display: inline-block; vertical-align: middle; margin-right: 4px; color: #4b736b; }
  .block { display: block; }
  .turnos-badge {
    font-size: 0.82rem; font-weight: 700; color: #1f5f51;
  }
  .booked-tag { color: #d97706; margin-left: 4px; font-weight: 600; }
  .actions-cell { display: flex; align-items: center; gap: 8px; }
  .icon-btn { display: inline-flex; align-items: center; gap: 4px; padding: 6px 10px; }
  .pill.free { background: #eef7f2; color: #236d5a; }
  .date-filter { display: flex; align-items: center; gap: 8px; font-size: 0.85rem; }
  .date-filter select { padding: 6px 10px; border-radius: 8px; border: 1px solid #cedcd6; font-size: 0.85rem; }
  .gap-10 { display: flex; align-items: center; gap: 12px; }

  @media (max-width: 900px) {
    .shift-form { grid-template-columns: 1fr; }
    .preset-buttons { grid-template-columns: 1fr; }
    .break-inputs { grid-template-columns: 1fr; }
  }
</style>
