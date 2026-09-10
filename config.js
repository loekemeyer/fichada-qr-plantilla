// ============================================================================
// Config del DEPÓSITO. Este archivo SÍ se sube: la URL y el anon key son
// públicos por diseño (viajan al navegador de cualquier operario que fiche).
//
// Lo que NO está acá y nunca puede estar: el secreto de firma HMAC, la clave de
// la pantalla y la clave del panel. Esas tres viven solo en fichada.config,
// dentro de Postgres.
// ============================================================================
window.FICHADA_CFG = {
  // Nombre visible. Es el DEPÓSITO, no la empresa: en Virgilio fichan
  // operarios de Loeke, Chef y Agencia.
  deposito: "Virgilio",

  supabaseUrl:  "https://hrxfctzncixxqmpfhskv.supabase.co",
  supabaseAnon: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyeGZjdHpuY2l4eHFtcGZoc2t2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjQyNjEsImV4cCI6MjA4ODMwMDI2MX0.4L6wguch8UZGhC2VpzrWcCjJGUV-IkYsl9JoCWrOLUs",

  // Edge Functions de ESTE sistema. Ojo: NO son fichada-qr-*, que pertenecen
  // al sistema de fichada anterior y no se tocan.
  fnEmitir: "/functions/v1/deposito-emitir",
  fnMarcar: "/functions/v1/deposito-marcar",
  fnPanel:  "/functions/v1/deposito-panel",

  // Cada cuánto rota el QR en pantalla. El vencimiento real lo manda el
  // servidor (config.token_ttl_seg = 40 s). Mantenerlos parecidos.
  periodoSeg: 30,
};
