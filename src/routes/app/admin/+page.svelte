<script lang="ts">
  import { dateTime, dateOnly, timeOnly, dateKey, shiftTypeLabel } from '$lib/format';
  import { Clock3, Coffee, CalendarPlus, Edit3, Trash2, AlertCircle, CheckCircle } from 'lucide-svelte';

  let { data, form } = $props();

  const todayLima = dateKey(new Date());

  // Form state para gestión de jornada por admin
  let shiftId = $state<string | null>(null);
  let doctorId = $state('');
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
    doctorId = s.doctor_id;
    workDate = s.work_date;
    shiftType = s.shift_type;
    startTime = timeOnly(s.starts_at);
    endTime = timeOnly(s.ends_at);
    hasBreak = Boolean(s.break_starts_at && s.break_ends_at);
    if (hasBreak) {
      breakStartTime = timeOnly(s.break_starts_at);
      breakEndTime = timeOnly(s.break_ends_at);
    }
  }

  function cancelEdit() {
    shiftId = null;
    doctorId = '';
    workDate = todayLima;
    applyPreset('full_day');
  }
</script>

<svelte:head>
  <title>Administración · CitaCloud</title>
</svelte:head>

<span class="eyebrow">CONFIGURACIÓN DE LA CLÍNICA</span>
<h1>Administración</h1>
<p class="muted">Asigna funciones al personal, registra médicos y gestiona las jornadas de atención médica.</p>

{#if form?.message}
  <div class="alert"><AlertCircle size={18} /> {form.message}</div>
{/if}
{#if form?.success}
  <div class="alert success"><CheckCircle size={18} /> {form.success}</div>
{/if}

<div class="admin-grid">
  <section class="card">
    <h2>1. Asignar rol</h2>
    <p class="muted small">Las cuentas se registran como pacientes. Cambia el rol del personal aquí.</p>
    <form method="POST" action="?/role" class="stack">
      <div>
        <label for="user">Cuenta</label>
        <select name="user_id" id="user" required>
          <option value="">Elegir usuario</option>
          {#each data.profiles as p}
            <option value={p.id}>{p.full_name} · {p.role}</option>
          {/each}
        </select>
      </div>
      <div>
        <label for="role">Nuevo rol</label>
        <select name="role" id="role">
          <option value="doctor">Médico</option>
          <option value="reception">Recepción</option>
          <option value="patient">Paciente</option>
          <option value="admin">Administrador</option>
        </select>
      </div>
      <button class="btn" type="submit">Guardar rol</button>
    </form>
  </section>

  <section class="card">
    <h2>2. Dar de alta a un médico</h2>
    <p class="muted small">La cuenta debe tener el rol de médico antes de este paso.</p>
    <form method="POST" action="?/doctor" class="stack">
      <div>
        <label for="doctor-user">Cuenta médica</label>
        <select name="user_id" id="doctor-user" required>
          <option value="">Elegir cuenta</option>
          {#each data.profiles.filter((p: any) => p.role === 'doctor' && !data.doctors.some((d: any) => d.profile_id === p.id)) as p}
            <option value={p.id}>{p.full_name}</option>
          {/each}
        </select>
      </div>
      <div>
        <label for="specialty">Especialidad</label>
        <select name="specialty_id" id="specialty" required>
          {#each data.specialties as s}
            <option value={s.id}>{s.name}</option>
          {/each}
        </select>
      </div>
      <button class="btn secondary" type="submit">Añadir médico</button>
    </form>
  </section>
</div>

<!-- 3. Gestionar jornadas de atención médica -->
<section class="card">
  <h2>3. Gestionar jornadas de atención médica</h2>
  <p class="muted small">
    Configura la jornada de un médico por fecha. El sistema generará automáticamente turnos de 30 minutos disponibles para los pacientes (hora local de Perú America/Lima).
  </p>

  {#if shiftId}
    <div class="editing-banner">
      <span>Editando jornada existente.</span>
      <button type="button" class="btn small text" onclick={cancelEdit}>Cancelar edición</button>
    </div>
  {/if}

  <form method="POST" action="?/save_shift" class="shift-admin-form">
    {#if shiftId}
      <input type="hidden" name="shift_id" value={shiftId} />
    {/if}

    <div class="row-fields">
      <div>
        <label for="doctor-select">Médico</label>
        <select name="doctor_id" id="doctor-select" bind:value={doctorId} required>
          <option value="">Elegir médico</option>
          {#each data.doctors as d}
            <option value={d.id}>{d.profile?.full_name} · {d.specialty?.name}</option>
          {/each}
        </select>
      </div>

      <div>
        <label for="shift-date">Fecha de atención</label>
        <input class="input" id="shift-date" type="date" name="work_date" bind:value={workDate} min={todayLima} required />
      </div>

      <div>
        <label for="shift-type-select">Modalidad</label>
        <select
          id="shift-type-select"
          name="shift_type"
          bind:value={shiftType}
          onchange={() => applyPreset(shiftType)}
        >
          <option value="full_day">Día completo (08:00 – 19:00)</option>
          <option value="half_day">Medio día (08:00 – 13:00)</option>
          <option value="custom">Personalizado</option>
        </select>
      </div>
    </div>

    <div class="row-fields times-row">
      <div>
        <label for="admin-start">Hora de inicio</label>
        <input class="input" id="admin-start" type="time" name="start_time" bind:value={startTime} required />
      </div>

      <div>
        <label for="admin-end">Hora de fin</label>
        <input class="input" id="admin-end" type="time" name="end_time" bind:value={endTime} required />
      </div>

      <div class="break-toggle-col">
        <label class="checkbox-label">
          <input type="checkbox" name="has_break" bind:checked={hasBreak} />
          <span><Coffee size={15} /> Incluir descanso opcional</span>
        </label>
      </div>
    </div>

    {#if hasBreak}
      <div class="row-fields break-fields">
        <div>
          <label for="admin-break-start">Inicio del descanso</label>
          <input class="input" id="admin-break-start" type="time" name="break_start_time" bind:value={breakStartTime} required={hasBreak} />
        </div>
        <div>
          <label for="admin-break-end">Fin del descanso</label>
          <input class="input" id="admin-break-end" type="time" name="break_end_time" bind:value={breakEndTime} required={hasBreak} />
        </div>
      </div>
    {/if}

    <div class="form-submit-row">
      <button class="btn" type="submit">
        <CalendarPlus size={16} /> {shiftId ? 'Actualizar jornada' : 'Publicar jornada y generar turnos'}
      </button>
    </div>
  </form>
</section>

<!-- Listado de Jornadas Registradas -->
<section class="card">
  <h2>Jornadas médicas programadas</h2>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>Médico</th>
          <th>Fecha</th>
          <th>Modalidad</th>
          <th>Horario</th>
          <th>Descanso</th>
          <th>Acciones</th>
        </tr>
      </thead>
      <tbody>
        {#each data.shifts as s}
          <tr>
            <td>
              <strong>{s.doctor?.profile?.full_name}</strong>
              <small class="muted block">{s.doctor?.specialty?.name}</small>
            </td>
            <td>{dateOnly(s.starts_at)}</td>
            <td><span class="pill">{shiftTypeLabel(s.shift_type)}</span></td>
            <td><Clock3 size={13} class="inline-icon" /> {timeOnly(s.starts_at)} – {timeOnly(s.ends_at)}</td>
            <td>
              {#if s.break_starts_at && s.break_ends_at}
                <Coffee size={13} class="inline-icon" /> {timeOnly(s.break_starts_at)} – {timeOnly(s.break_ends_at)}
              {:else}
                <span class="muted">Sin descanso</span>
              {/if}
            </td>
            <td>
              <div class="actions-cell">
                <button type="button" class="btn secondary small icon-btn" onclick={() => editShift(s)} title="Editar">
                  <Edit3 size={14} /> Editar
                </button>
                <form method="POST" action="?/delete_shift" onsubmit={(e) => { if (!confirm('¿Eliminar esta jornada? No es posible si tiene citas confirmadas.')) e.preventDefault(); }}>
                  <input type="hidden" name="shift_id" value={s.id} />
                  <button type="submit" class="btn danger small icon-btn" title="Eliminar">
                    <Trash2 size={14} />
                  </button>
                </form>
              </div>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if !data.shifts.length}
    <div class="empty">Todavía no hay jornadas médicas registradas.</div>
  {/if}
</section>

<!-- Resumen de Turnos Próximos de 30m -->
<section class="card">
  <h2>Próximos turnos reservables (30 min)</h2>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>Médico</th>
          <th>Turno y fecha</th>
          <th>Estado</th>
        </tr>
      </thead>
      <tbody>
        {#each data.slots.slice(0, 30) as s}
          {@const isReserved = data.appointments.some((a: any) => a.slot_id === s.id)}
          <tr>
            <td>{s.doctor?.profile?.full_name}</td>
            <td>{dateTime(s.starts_at)}</td>
            <td>
              {#if isReserved}
                <span class="pill cancelled">Reservado</span>
              {:else}
                <span class="pill">Libre</span>
              {/if}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if !data.slots.length}
    <div class="empty">No hay turnos disponibles próximamente.</div>
  {/if}
</section>

<style>
  h1 { font-size: 2.2rem; margin: 7px 0; }
  .card { margin-top: 22px; }
  .card h2 { font-size: 1.2rem; }
  .admin-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
  .editing-banner {
    background: #fff8e6; border: 1px solid #fed888; color: #875a00;
    padding: 10px 14px; border-radius: 8px; margin: 14px 0;
    display: flex; justify-content: space-between; align-items: center; font-size: 0.88rem;
  }
  .shift-admin-form { display: grid; gap: 14px; margin-top: 14px; }
  .row-fields { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; }
  .times-row { align-items: end; }
  .break-toggle-col { padding-bottom: 8px; }
  .checkbox-label {
    display: inline-flex; align-items: center; gap: 8px; font-weight: 600;
    font-size: 0.88rem; color: #284441; cursor: pointer;
  }
  .checkbox-label input { width: 17px; height: 17px; accent-color: #287562; }
  .break-fields { grid-template-columns: 1fr 1fr; background: #fbfdfc; padding: 12px; border-radius: 8px; border: 1px solid #e7efe9; }
  .form-submit-row { display: flex; justify-content: flex-end; }
  :global(.inline-icon) { display: inline-block; vertical-align: middle; margin-right: 3px; color: #4b736b; }
  .block { display: block; }
  .actions-cell { display: flex; align-items: center; gap: 6px; }
  .icon-btn { display: inline-flex; align-items: center; gap: 4px; }

  @media (max-width: 900px) {
    .admin-grid { grid-template-columns: 1fr; }
    .row-fields { grid-template-columns: 1fr; }
  }
</style>
