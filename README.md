# Fichada QR — Plantilla

Control de presencia (fichada / check-in) por **QR rotativo**, sin pedir ubicación.
Una **pantalla fija** en el lugar de trabajo muestra un QR que cambia cada ~30 s;
el empleado lo escanea, confirma su correo y queda registrada la fichada del día.

Es una **plantilla multi-empresa**: el código es uno solo, y cada empresa se
despliega con **su propio proyecto Supabase** y su propia config. Los datos de una
empresa nunca se cruzan con los de otra.

## Cómo evita la fichada trucha

- El token del QR está **firmado (HMAC-SHA256)** y **vence en segundos**. El
  secreto de firma vive **solo en Supabase**, nunca en el navegador → una foto
  vieja del QR ya no sirve (el servidor la rechaza con `token_vencido`).
- **1 fichada por día** garantizada por base de datos (`UNIQUE(correo, fecha)`).
- Solo la **pantalla on-site** (con la *clave de dispositivo*) puede emitir tokens.

> Límite honesto: dentro de la ventana de ~30 s, alguien podría reenviar el QR
> por WhatsApp a un compañero. Para cerrar eso está la capa **opcional de IP de
> la empresa** (ver `supabase/README.md`), que exige estar en la red del trabajo.
> Nada garantiza presencia física al 100 % sin geolocalización o hardware.

## Estructura

```
index.html            Portada con dos accesos (Pantalla / Fichar)
pantalla.html         Dispositivo fijo: muestra el QR rotativo
fichar.html           Se abre al escanear: confirma correo y registra
config.example.js     Config por empresa (copiar a config.js — NO se sube)
supabase/
  migrations/         Esquema + funciones SQL (firma HMAC, 1/día)
  functions/          Edge Functions (emitir-token, fichar)
  README.md           Deploy del backend, paso a paso
```

## Dar de alta una empresa nueva (resumen)

1. **Backend:** crear un proyecto Supabase para la empresa y aplicar
   `supabase/migrations/` + desplegar `supabase/functions/`.
   → Pasos detallados en [`supabase/README.md`](supabase/README.md).
2. **Correos habilitados:** cargar la lista en la tabla `fichada.empleados`.
3. **Config del sitio:** `cp config.example.js config.js` y completar
   `supabaseUrl`, `supabaseAnon` y `empresa`.
4. **Publicar** `index.html` / `pantalla.html` / `fichar.html` (GitHub Pages,
   Vercel o Netlify).
5. **Pantalla on-site:** abrir `pantalla.html#clave=LA_CLAVE_DE_DISPOSITIVO` en
   el dispositivo fijo (la clave sale de `fichada.config`, ver guía del backend).

## Probar sin backend

Abrí `index.html` directamente: la pantalla rota un QR de **demo** y `fichar.html`
simula un OK. Sirve para ver el diseño y el flujo. Para producción, seguí los pasos
de arriba.
