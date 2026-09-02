# Backend (Supabase) — deploy por empresa

Cada empresa usa **su propio proyecto Supabase**. Repetir estos pasos por empresa.

## 1. Crear el proyecto

1. En https://supabase.com → **New project**. Elegí región cercana.
2. Anotá el **Project URL** (`https://XXXX.supabase.co`) y el **anon key**
   (Settings → API). El anon key es público, va en `config.js`.

## 2. Aplicar las migraciones

En **SQL Editor** del proyecto, pegá y ejecutá **en orden**:

1. `migrations/0001_schema.sql` — crea el esquema `fichada`, las tablas y la
   config (genera al azar el secreto de firma y la clave de dispositivo).
2. `migrations/0002_funciones.sql` — crea las funciones de firma/validación.

## 3. Ver la clave de dispositivo (y el TTL)

```sql
select clave_dispositivo, token_ttl_seg from fichada.config where id = 1;
```

- `clave_dispositivo` → la usás en la pantalla: `pantalla.html#clave=ESA_CLAVE`.
- `token_ttl_seg` → cuántos segundos vive cada código (por defecto **40**).

Para **rotar** la clave (invalida la anterior):

```sql
update fichada.config
   set clave_dispositivo = substr(replace(gen_random_uuid()::text,'-',''),1,20)
 where id = 1;
```

Cambiar el nombre de la empresa y la zona horaria:

```sql
update fichada.config
   set empresa_nombre = 'ACME S.A.',
       zona_horaria   = 'America/Argentina/Buenos_Aires'
 where id = 1;
```

## 4. Cargar los correos habilitados

```sql
insert into fichada.empleados (correo, nombre) values
  ('ana@empresa.com',  'Ana Pérez'),
  ('juan@empresa.com', 'Juan Gómez');
-- Dar de baja sin borrar:  update fichada.empleados set activo=false where correo='...';
```

## 5. Desplegar las Edge Functions

Con la [CLI de Supabase](https://supabase.com/docs/guides/cli), logueada y
enlazada al proyecto (`supabase link`):

```bash
supabase functions deploy emitir-token --no-verify-jwt
supabase functions deploy fichar       --no-verify-jwt
```

`--no-verify-jwt` es a propósito: la autenticación real es la **clave de
dispositivo** (emitir) y el **token firmado** (fichar), no un JWT de Supabase.
`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` ya están disponibles como env vars
de las funciones — no hace falta configurarlas.

## 6. Probar (curl, desde una máquina con internet)

```bash
BASE="https://XXXX.supabase.co/functions/v1"
ANON="TU_ANON_KEY"
CLAVE="TU_CLAVE_DE_DISPOSITIVO"

# emitir un token
TOKEN=$(curl -s -X POST "$BASE/emitir-token" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  -H "x-clave-dispositivo: $CLAVE" | sed -E 's/.*"token":"([^"]+)".*/\1/')

# fichar con ese token
curl -s -X POST "$BASE/fichar" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"email\":\"ana@empresa.com\"}"
```

Respuestas esperadas: `{"ok":true,"hora":"HH:MM"}`, luego `{"error":"ya_ficho",...}`
al repetir; `{"error":"no_habilitado"}` con un correo fuera de la lista;
`{"error":"token_vencido"}` con un token viejo.

## 7. (Opcional) Capa "solo desde la fábrica" por IP

Requiere **IP pública fija y sin CGNAT** en la empresa.

```sql
update fichada.config set ip_trabajo = '200.x.x.x' where id = 1;
```

Luego activar el chequeo en `functions/fichar/index.ts` (hay un bloque comentado
que lee `x-forwarded-for`). Se saltea con VPN/datos móviles, por eso va como
**complemento** del QR rotativo, no como única defensa.

## Modelo de seguridad (resumen)

- Secreto de firma: **solo** en `fichada.config` (Postgres). Nunca en el navegador.
- Funciones `SECURITY DEFINER`, ejecutables **solo por `service_role`**.
- El esquema `fichada` no se expone en la API pública (PostgREST).
- `UNIQUE(correo, fecha)` = 1 fichada por día, a prueba de carreras.
