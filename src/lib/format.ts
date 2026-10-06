export const dateTime = (value: string) =>
  new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(value));

export const dateOnly = (value: string) =>
  new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' }).format(new Date(value));

export const dateShort = (value: string | Date) =>
  new Intl.DateTimeFormat('es-PE', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'America/Lima' }).format(typeof value === 'string' ? new Date(value) : value);

export const timeOnly = (value: string | Date) =>
  new Intl.DateTimeFormat('es-PE', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Lima' }).format(typeof value === 'string' ? new Date(value) : value);

export const dateKey = (value: string | Date) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(typeof value === 'string' ? new Date(value) : value);

export const statusLabel = (value: string) =>
  ({ confirmed: 'Confirmada', cancelled: 'Cancelada', completed: 'Atendida' } as Record<string, string>)[value] ?? value;

export const shiftTypeLabel = (value: string) =>
  ({ full_day: 'Día completo', half_day: 'Medio día', custom: 'Personalizado' } as Record<string, string>)[value] ?? value;
