-- ============================================================================
-- Fichada QR — Plantilla — Fase 1 (MVP)
-- Esquema aislado "fichada". Cada empresa despliega esto en SU propio proyecto
-- Supabase. No hay datos de otra empresa: un proyecto = una empresa.
-- Las Edge Functions entran con service_role (ignora RLS).
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists fichada;

-- Lista blanca de correos habilitados para fichar.
create table if not exists fichada.empleados (
  correo     text primary key,
  nombre     text,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Registro de fichadas. UNIQUE(correo, fecha) => 1 fichada por día (atómico).
create table if not exists fichada.fichadas (
  id         bigint generated always as identity primary key,
  correo     text not null,
  fecha      date not null,
  creado_en  timestamptz not null default now(),
  unique (correo, fecha)
);

-- Auditoría de tokens canjeados (jti, correo).
create table if not exists fichada.tokens_usados (
  jti       text not null,
  correo    text not null,
  usado_en  timestamptz not null default now(),
  primary key (jti, correo)
);

-- Config de la empresa: secreto de firma + clave de dispositivo + TTL del token.
-- ip_trabajo queda preparada para la capa opcional de "solo desde la fábrica".
create table if not exists fichada.config (
  id                 integer primary key default 1,
  token_secret       text not null,
  clave_dispositivo  text not null,
  token_ttl_seg      integer not null default 40,   -- un poco > que la rotación (30s) por desfase de reloj
  ip_trabajo         text,                            -- null = chequeo de IP desactivado
  zona_horaria       text not null default 'America/Argentina/Buenos_Aires',
  empresa_nombre     text not null default 'Tu Empresa',
  constraint config_fila_unica check (id = 1)
);

-- RLS por higiene (service_role lo ignora; ningún cliente anon llega al schema).
alter table fichada.empleados     enable row level security;
alter table fichada.fichadas      enable row level security;
alter table fichada.tokens_usados enable row level security;
alter table fichada.config        enable row level security;

-- Semilla de config: secreto (64 hex) y clave de dispositivo (20 hex) al azar.
insert into fichada.config (id, token_secret, clave_dispositivo)
values (
  1,
  replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  substr(replace(gen_random_uuid()::text, '-', ''), 1, 20)
)
on conflict (id) do nothing;
