# CitaCloud

Prototipo académico de citas médicas en la nube. **Usa exclusivamente datos ficticios.**

## Qué incluye

- **Pacientes**: registro, inicio de sesión, calendario por médico y fecha, horas disponibles de 30 minutos, reserva atómica, cancelación e historial de atenciones.
- **Médicos**: configuración de jornadas de atención por fecha ("Día completo", "Medio día", "Personalizado", con ajuste horario y descanso opcional), consulta de turnos de 30 minutos generados y confirmación de atención completada.
- **Recepción**: reserva asistida para pacientes sobre turnos libres de 30 minutos y consulta de citas.
- **Administración**: gestión de roles, alta de médicos, gestión de jornadas médicas de cualquier doctor y trazabilidad.
- **Seguridad**: MFA TOTP (AAL2) obligatorio para el personal de salud (médico, recepción, admin), permisos granulares en PostgreSQL con Row Level Security (RLS), reservas atómicas con bloqueo de fila (`for update`) y auditoría de creación/modificación de jornadas y citas.
- **Capacitación**: lección de ciberseguridad sobre phishing, evaluación y registro de resultados.
- **Zona Horaria**: soporte nativo para `America/Lima` (UTC−05:00) tanto en la interfaz como en el almacenamiento de timestamps en PostgreSQL.

## Tecnologías

SvelteKit, TypeScript, Supabase Auth, PostgreSQL, Supabase Row Level Security y despliegue compatible con Vercel. La aplicación web y la base de datos están desacopladas.

## Requisitos previos

Node.js 20 o superior, npm, una cuenta de Supabase. Vercel solo si se va a publicar. No necesitas PHP, XAMPP ni MySQL.

## Instalación paso a paso

1. Descomprime o clona el proyecto y abre la carpeta `citacloud` en tu terminal o editor.
2. Instala las dependencias:

   ```bash
   npm install
   ```

3. Crea un proyecto en [Supabase](https://supabase.com/dashboard).
4. En **SQL Editor**, ejecuta las migraciones en orden:
   - Si es un proyecto completamente nuevo: ejecuta primero `supabase/migrations/001_initial.sql` y a continuación `supabase/migrations/002_doctor_shifts.sql`.
   - Si tu proyecto ya tiene la migración inicial ejecutada: consulta la sección [Aplicar la nueva migración (002_doctor_shifts.sql)](#aplicar-la-nueva-migración-002_doctor_shiftssql).
5. En Supabase, entra en **Project Settings → API** y copia la URL del proyecto y la clave pública **publishable**. No copies `service_role` ni ninguna clave secreta al frontend.
6. Copia `.env.example` como `.env` y configura tus variables:

   ```env
   PUBLIC_SUPABASE_URL=https://tu-proyecto.supabase.co
   PUBLIC_SUPABASE_PUBLISHABLE_KEY=tu_clave_publica
   ```

7. En **Authentication → URL Configuration**, usa `http://localhost:5173` como Site URL durante el desarrollo y agrega `http://localhost:5173/auth/callback` a Redirect URLs. Si publicas en producción, agrega también `https://tu-dominio/auth/callback`.
8. Inicia el servidor de desarrollo:

   ```bash
   npm run dev
   ```

   Abre `http://localhost:5173`.

---

## Aplicar la nueva migración (`002_doctor_shifts.sql`)

Si tu proyecto de Supabase ya tiene ejecutada la migración inicial `001_initial.sql` y contiene datos, citas o turnos creados:

1. Entra al dashboard de tu proyecto en Supabase y dirígete a **SQL Editor**.
2. Haz clic en **New query** (Nueva consulta).
3. Abre el archivo local `supabase/migrations/002_doctor_shifts.sql`, copia todo su contenido y pégalo en el editor SQL de Supabase.
4. Presiona el botón **Run** (Ejecutar).

Antes de ejecutar la migración en una base con datos reales, crea una copia de seguridad. Esta versión sustituye el archivo 002 recibido; si ya ejecutaste una versión anterior de 002, no vuelvas a ejecutar todo el archivo: se necesita una migración de reparación específica para el estado actual de tu base.

Al reemplazar el proyecto en tu computadora, conserva tu propio archivo `.env` con la URL y clave pública de Supabase. El ZIP de entrega incluye `.env.example` y no incluye credenciales.

### ¿Qué hace esta migración?
- **Crea la tabla `public.doctor_shifts`** para registrar las jornadas de trabajo médico por fecha (`work_date`), tipo (`full_day`, `half_day`, `custom`), horas de inicio y fin (`starts_at`, `ends_at`) y horarios de descanso opcional (`break_starts_at`, `break_ends_at`).
- **Preserva todos los datos existentes**: agrega la columna `shift_id` a `public.schedule_slots` sin eliminar ningún turno ni cita anterior. Además, agrupa y asocia automáticamente los turnos existentes a jornadas correspondientes.
- **Implementa la función `save_doctor_shift`**:
  - Valida permisos por rol (`doctor` para su propia cuenta o `admin` para cualquier médico) y exige segundo factor (AAL2).
  - Evita jornadas superpuestas para el mismo médico.
  - **Protege citas confirmadas**: si se modifica una jornada existente, verifica que ninguna cita ya reservada quede fuera del nuevo rango horario o caiga dentro del horario de descanso. Si existe conflicto, aborta la operación indicando la hora de la cita afectada.
  - Genera automáticamente los turnos reservables de 30 minutos dentro de la jornada y excluye el periodo de descanso.
  - Registra la acción en `public.audit_logs` (`shift.created` o `shift.updated`).
- **Implementa la función `delete_doctor_shift`**: protege las citas confirmadas impidiendo eliminar jornadas con citas activas y audita la eliminación (`shift.deleted`).
- **Protege la disponibilidad**: las reservas solo aceptan turnos de 30 minutos dentro de una jornada vigente. Los turnos históricos cancelados se conservan para el historial, pero dejan de aparecer cuando se elimina o modifica su jornada.
- **Deshabilita `admin_add_slot`**: la administración publica jornadas desde su panel; la antigua función de intervalos libres ya no se utiliza.

---

## Crear el primer administrador

1. Registra una cuenta desde `/register`. Todas las cuentas nuevas se crean como `patient` para evitar escalada no autorizada.
2. Desde el **SQL Editor** de Supabase, asigna el rol de administrador a tu cuenta ejecutando:

   ```sql
   update public.profiles p
   set role = 'admin'
   from auth.users u
   where p.id = u.id and u.email = 'tu-correo@ejemplo.com';
   ```

3. Cierra sesión en la web, vuelve a ingresar y dirígete a **Seguridad**. Configura el segundo factor con Google Authenticator u otra app TOTP y verifica el código de 6 dígitos. Una vez verificado, tendrás acceso al panel de administración.

---

## Flujo de Demostración: Jornadas y Reserva de Turnos

### 1. Rol Médico (Ejemplo: Jhon)
1. El administrador asigna el rol `doctor` al usuario y lo da de alta con una especialidad (ej. Medicina General).
2. El médico activa su segundo factor (MFA) en `/app/seguridad`.
3. El médico ingresa a **Agenda médica** (`/app/agenda`):
   - Selecciona la fecha deseada (ej. `07/10/2026`).
   - Elige la modalidad:
     - **Día completo**: preconfigura de 08:00 a 19:00 con descanso de 13:00 a 14:00.
     - **Medio día**: preconfigura de 08:00 a 13:00 sin descanso.
     - **Personalizado**: permite ajustar horas de inicio, fin y descanso libremente.
   - Presiona **Publicar jornada y generar turnos**.
   - El sistema genera automáticamente los turnos de 30 minutos: 08:00–08:30, 08:30–09:00, ..., hasta 18:30–19:00 (omitiendo el descanso de 13:00 a 14:00).
   - El médico puede editar o eliminar sus jornadas desde la tabla inferior.

### 2. Rol Paciente (Ejemplo: Anthoni)
1. El paciente ingresa a **Mis citas** (`/app/citas`).
2. Filtra por especialidad y selecciona al médico (ej. Dr. Jhon).
3. Selecciona la fecha en el calendario o en la tira de fechas disponibles (ej. `07/10/2026`).
4. Visualiza los turnos libres de 30 minutos: 08:00, 08:30, 09:00, ..., 12:30, 14:00, ..., 18:30.
5. Selecciona un turno concreto (ej. `10:00`) y presiona **Confirmar reserva**.
6. **Resultado**:
   - Solo el turno de las `10:00` pasa a estado ocupado y desaparece de la cuadrícula de horas disponibles.
   - El resto de los turnos continúan libres y disponibles para otros pacientes.
   - La cita queda registrada en su historial con opción de cancelación.

### 3. Rol Administrador
1. El administrador puede acceder a **Administración** (`/app/admin`) y gestionar directamente las jornadas de cualquier médico, visualizar turnos y auditar la actividad en `/app/auditoria`.

---

## Estructura del Proyecto

```text
src/routes/                 Páginas, endpoints y acciones del servidor
src/routes/app/citas/       Calendario por médico/fecha y reserva atómica de turnos de 30m
src/routes/app/agenda/      Panel médico: jornadas de atención (presets/descanso) y turnos
src/routes/app/recepcion/   Reservas asistidas para pacientes
src/routes/app/admin/       Administración de usuarios, médicos y jornadas
src/routes/app/seguridad/   Configuración de segundo factor MFA TOTP
src/routes/app/capacitacion/Lección interactiva y evaluación sobre phishing
src/routes/app/auditoria/   Registro de auditoría (jornadas, citas, roles)
src/lib/server/auth.ts      Validación de roles y nivel de aseguramiento AAL2
src/lib/format.ts           Formateo de fechas, horas y textos en zona horaria America/Lima
supabase/migrations/
  ├── 001_initial.sql       Esquema inicial (perfiles, médicos, citas, auditoría, RLS)
  └── 002_doctor_shifts.sql Gestión de jornadas de atención, turnos de 30m y protección de citas
```

## Verificación y Compilación

Para comprobar que el proyecto no contiene errores de tipos ni de sintaxis:

```bash
npm run check
npm run build
```
