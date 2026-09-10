# Backend (Supabase) — deploy por depósito

Cada depósito usa su propio esquema `fichada`. Puede convivir con otras cosas en
el mismo proyecto: **nada de lo que hay acá toca tablas ni funciones ajenas**.
Los nombres están prefijados para que no choquen (`fichada.*`, `fichada_dep_*`,
Edge Functions `deposito-*`).

## 1. Aplicar las migraciones

En el **SQL Editor** del proyecto, pegar y ejecutar **en orden**:

1. `migrations/0001_esquema.sql` — esquema, tablas y config (genera al azar el
   secreto de firma y las **dos** claves).
2. `migrations/0002_funciones.sql` — firma/validación del token y máquina de estados.
3. `migrations/0003_panel.sql` — la puerta del panel de RR. HH.
4. `migrations/0004_datos_iniciales.sql` — padrón inicial. **Editar antes de correr.**

Requiere `pgcrypto` en el esquema `extensions` (en Supabase viene así por defecto):

```sql
select n.nspname from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgcrypto';
```

## 2. Ver las claves

```sql
select deposito, clave_dispositivo, clave_panel, token_ttl_seg
  from fichada.config where id = 1;
```

- `clave_dispositivo` → `pantalla.html#clave=ESA_CLAVE`, en el dispositivo fijo.
- `clave_panel` → se pega en la puerta de `panel.html`.

Lo normal es rotarlas desde el panel → **Ajustes**. Esto es el plan B, para
cuando se perdió la clave del panel y no se puede entrar:

```sql
update fichada.config
   set clave_dispositivo = substr(replace(gen_random_uuid()::text,'-',''),1,20)
 where id = 1;
```

## 3. Ajustar la jornada del depósito

De acá salen los rojos del panel y la columna `Dif.`. Un solo lugar.

```sql
update fichada.config
   set deposito       = 'Virgilio',
       hora_entrada   = '08:00',
       hora_salida    = '17:00',
       comida_min     = 30,     -- comida pactada, se descuenta del objetivo
       tolerancia_min = 5,      -- sin esto, entrar 08:01 se pinta rojo
       rebote_seg     = 120,    -- anti doble escaneo
       zona_horaria   = 'America/Argentina/Buenos_Aires'
 where id = 1;
```

Objetivo neto = (salida − entrada) − comida. Con 08:00–17:00 y 30 min → **8:30**.

## 4. Desplegar las Edge Functions

Con la [CLI de Supabase](https://supabase.com/docs/guides/cli) enlazada al proyecto:

```bash
supabase functions deploy deposito-emitir --no-verify-jwt
supabase functions deploy deposito-marcar --no-verify-jwt
supabase functions deploy deposito-panel  --no-verify-jwt
```

`--no-verify-jwt` es a propósito: la autenticación real es la **clave de
dispositivo** (emitir), el **token firmado** (marcar) y la **clave de panel**.
`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` ya existen como env vars.

## 5. Probar (curl)

```bash
BASE="https://XXXX.supabase.co/functions/v1"
ANON="TU_ANON_KEY"
DISP="TU_CLAVE_DE_DISPOSITIVO"
H=(-H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json")

TOKEN=$(curl -s -X POST "$BASE/deposito-emitir" "${H[@]}" \
  -H "x-clave-dispositivo: $DISP" -d '{}' | sed -E 's/.*"token":"([^"]+)".*/\1/')

# qué puede fichar (no consume el token)
curl -s -X POST "$BASE/deposito-marcar" "${H[@]}" \
  -d "{\"token\":\"$TOKEN\",\"email\":\"alguien@empresa.com\"}"

# registrar la marca (consume el token)
curl -s -X POST "$BASE/deposito-marcar" "${H[@]}" \
  -d "{\"token\":\"$TOKEN\",\"email\":\"alguien@empresa.com\",\"tipo\":\"entrada\"}"
```

Errores esperados: `clave_invalida`, `token_vencido`, `token_invalido`,
`token_usado` (replay), `no_habilitado`, `tipo_no_permitido`, `rebote`.

## 6. (Opcional) Capa "solo desde el depósito" por IP

Requiere **IP pública fija y sin CGNAT**.

```sql
update fichada.config set ip_trabajo = '200.x.x.x' where id = 1;
```

Falta activar el chequeo en `deposito-marcar` (leer `x-forwarded-for` y comparar
del lado servidor). Se saltea con VPN o datos móviles, por eso va como
**complemento** del QR rotativo, no como única defensa.

## Modelo de seguridad

- Secreto de firma y ambas claves: **solo** en `fichada.config`. Nunca en el navegador.
- Funciones `SECURITY DEFINER` con `search_path = ''`, ejecutables **solo por `service_role`**.
- El esquema `fichada` no se expone en la API pública: PostgREST solo ve `public`,
  y las funciones de `public` tienen el `execute` revocado a `anon` y `authenticated`.
- `jti` único en `fichada.marcas` = un token vale una sola marca.
- El anon key es público por diseño: no alcanza para llegar a ninguna de estas funciones.
