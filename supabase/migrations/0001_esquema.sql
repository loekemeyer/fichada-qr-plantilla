-- ============================================================================
-- Fichada QR por depósito — esquema aislado "fichada".
-- NO toca el sistema existente (esquema "FichadaQR", tablas Fichadas_*).
-- Un depósito por proyecto; los empleados pueden ser de varias empresas.
-- ============================================================================

create schema if not exists fichada;

-- Config del depósito. Una sola fila.
create table if not exists fichada.config (
  id                 integer primary key default 1,
  deposito           text not null default 'Virgilio',
  token_secret       text not null,
  clave_dispositivo  text not null,   -- abre la pantalla del QR
  clave_panel        text not null,   -- abre el panel de RR. HH.
  token_ttl_seg      integer not null default 40,
  zona_horaria       text not null default 'America/Argentina/Buenos_Aires',
  hora_entrada       time not null default '08:00',
  hora_salida        time not null default '17:00',
  comida_min         integer not null default 30,
  tolerancia_min     integer not null default 5,
  rebote_seg         integer not null default 120,  -- anti doble escaneo
  ip_trabajo         text,
  constraint fichada_config_fila_unica check (id = 1)
);

-- Padrón. El correo es la identidad: es lo que el operario escribe al fichar.
create table if not exists fichada.empleados (
  id              bigint generated always as identity primary key,
  legajo          text not null,
  nombre          text not null,
  correo          text not null,
  empresa         text not null,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);
create unique index if not exists fichada_empleados_correo_uk
  on fichada.empleados (lower(correo));

-- Marcas del día. No hay tope: entrada, comida, permisos y fin de jornada.
-- comida_ini / comida_fin NO son salidas: comen dentro del depósito.
create table if not exists fichada.marcas (
  id          bigint generated always as identity primary key,
  correo      text not null,
  fecha       date not null,
  hora        time not null,
  tipo        text not null,
  origen      text not null default 'qr',
  jti         text,
  nota        text,
  creado_en   timestamptz not null default now(),
  constraint fichada_marcas_tipo_ck
    check (tipo in ('entrada','regreso','comida_ini','comida_fin','salida','fin')),
  constraint fichada_marcas_origen_ck
    check (origen in ('qr','manual'))
);
create index if not exists fichada_marcas_fecha_correo_ix
  on fichada.marcas (fecha, correo, hora);
-- Un token vale por una sola marca: mata el replay dentro de la ventana viva.
create unique index if not exists fichada_marcas_jti_uk
  on fichada.marcas (jti) where jti is not null;

-- RLS por higiene. El esquema no se expone en la API pública (PostgREST solo ve
-- "public"), y las Edge Functions entran con service_role, que ignora RLS.
alter table fichada.config    enable row level security;
alter table fichada.empleados enable row level security;
alter table fichada.marcas    enable row level security;

-- Semilla: secreto de firma (64 hex) + dos claves independientes.
-- Si se filtra la clave de la pantalla, el panel sigue cerrado.
insert into fichada.config (id, deposito, token_secret, clave_dispositivo, clave_panel)
values (
  1,
  'Virgilio',
  replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  substr(replace(gen_random_uuid()::text, '-', ''), 1, 20),
  substr(replace(gen_random_uuid()::text, '-', ''), 1, 20)
)
on conflict (id) do nothing;
