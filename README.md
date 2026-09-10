# Fichada QR — Depósito

Control de presencia por **QR rotativo**, sin pedir ubicación. Una **pantalla fija**
en el depósito muestra un QR que cambia cada ~30 s; el operario lo escanea con el
celular, confirma su correo, elige qué está fichando y queda registrado.

Se organiza **por depósito**, no por empresa: en Virgilio fichan operarios de
**Loeke, Chef y Agencia**, y cada fichada lleva la empresa del operario para que
RR. HH. liquide por separado.

## Las marcas

Un día no tiene un tope de marcas. Cada operario alterna entre trabajar y parar,
las veces que haga falta.

| Marca | Quién la elige | Sale del depósito |
|---|---|---|
| **Entrada** | nadie: es la primera del día | — |
| **Inicio comida** | el operario | no, comen adentro |
| **Fin comida** | el operario | no |
| **Permiso** | el operario | sí (médico, trámite) |
| **Regreso** | nadie: se deduce, estaba afuera | — |
| **Finalizar jornada** | el operario | sí |

Entrar y volver **nunca** se eligen: el servidor sabe si la persona está adentro
o afuera. Solo se elige al parar. La hora no condiciona nada: si alguien come a
las 14:10, marca *Inicio comida* a las 14:10 y cuenta como comida.

`Trabajado` es la suma de los tramos trabajando. `Dif.` lo compara contra el
objetivo neto (jornada menos comida pactada) y **solo se calcula con el día
cerrado**: a media mañana nadie está −8 h.

## Cómo evita la fichada trucha

- El token del QR está **firmado (HMAC-SHA256)** y **vence en 40 s**. El secreto
  vive **solo en Postgres**, nunca en el navegador → una foto vieja del QR se
  rechaza con `token_vencido`.
- **Un token = una marca.** El `jti` es único en la base: reenviar el mismo QR
  dos veces devuelve `token_usado`.
- **Anti doble escaneo:** dos marcas del mismo operario en menos de 2 minutos se
  rechazan con `rebote`.
- **Solo la pantalla del depósito** (con la clave de dispositivo) puede emitir tokens.
- **La hora la pone el servidor.** Cambiar la hora del celular no sirve de nada.

> Límite honesto: dentro de la ventana de ~30 s alguien podría reenviar el QR por
> WhatsApp. Para cerrar eso está la capa opcional de IP del depósito
> (`config.ip_trabajo`, ver `supabase/README.md`). Nada garantiza presencia
> física al 100 % sin geolocalización o hardware.

## Las cuatro pantallas

```
index.html      Portada con los tres accesos
pantalla.html   Dispositivo fijo del depósito: muestra el QR rotativo
fichar.html     Se abre al escanear: correo, qué fichás, listo
panel.html      RR. HH.: fichadas del día, horas, Excel y alta de operarios
config.js       URL + anon key del proyecto (públicos, por eso SÍ se sube)
supabase/       Migraciones y Edge Functions
```

## Las dos claves

Son **independientes a propósito**: si se filtra la de la pantalla, el panel sigue cerrado.

- **Clave de dispositivo** → se tipea al abrir `pantalla.html` en el dispositivo fijo.
  Queda guardada en esa pantalla y **no viaja en la barra de direcciones**: se pide
  una sola vez, no en cada arranque. Emite los tokens del QR.
- **Clave de panel** → `panel.html`, se pega en la puerta (o `panel.html#clave=LA_CLAVE`).
  El panel la guarda en ese dispositivo y la borra de la barra de direcciones.

Ambas se rotan desde el panel → pestaña **Ajustes**, sin entrar a Supabase. Ahí
también se ve y se copia la clave de la pantalla, para montar el dispositivo fijo.

Si rotás la clave de la pantalla, el dispositivo del depósito la pide sola en la
próxima rotación del QR: no hay que reabrir nada ni tocar SQL. Pero **hasta que
alguien la ponga, nadie puede fichar** — hacelo fuera del horario de entrada.

El panel **nunca** muestra su propia clave: quien está adentro ya la tiene, y así
no viaja por la red de más. Si la perdiste, se recupera por SQL
(ver `supabase/README.md`).

## Dar de alta un operario

Panel → pestaña **Operarios** → **Agregar operario**. Nombre, legajo, correo y
empresa. El **correo es la identidad**: es lo que la persona escribe al fichar y
no puede repetirse. Dar de baja no borra nada — deja de poder fichar, pero sus
fichadas viejas quedan para la liquidación.

## Dar de alta un depósito nuevo

1. Crear un proyecto Supabase para ese depósito.
2. Aplicar `supabase/migrations/` en orden y desplegar `supabase/functions/`.
   → Pasos detallados en [`supabase/README.md`](supabase/README.md).
3. Cargar el padrón (panel → Operarios, o `0004_datos_iniciales.sql`).
4. `config.js`: cambiar `deposito`, `supabaseUrl` y `supabaseAnon`.
5. Publicar. **Una sola vez:** Settings → Pages → Source: **GitHub Actions**.
   El token de Actions puede publicar pero no puede *crear* el sitio de Pages,
   así que ese switch va a mano. Después, `.github/workflows/pages.yml` sube el
   sitio en cada push a `main`.
6. Abrir `pantalla.html` en el dispositivo fijo del depósito y tipear ahí la clave
   del dispositivo (el panel la muestra y la copia, en Ajustes).

## Probar sin backend

Con un `config.js` cuyo `supabaseUrl` siga en `XXXX`, la pantalla rota un QR de
**demo** y las páginas muestran el diseño sin tocar la base. Sirve para revisar
el aspecto, no para producción.
