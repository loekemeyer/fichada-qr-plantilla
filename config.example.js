// ============================================================================
// Plantilla para dar de alta un DEPÓSITO nuevo: copiar a config.js y completar.
//
// config.js SÍ se sube al repo: solo lleva la URL del proyecto y el anon key,
// que son públicos por diseño (viajan al navegador de cualquier operario).
// Lo que nunca va acá: el secreto de firma HMAC, la clave de la pantalla y la
// clave del panel. Esas tres viven solo en fichada.config, dentro de Postgres.
// ============================================================================
window.FICHADA_CFG = {
  // Nombre visible. Es el DEPÓSITO, no la empresa: en un mismo depósito pueden
  // fichar operarios de varias empresas.
  deposito: "Nombre del depósito",

  supabaseUrl:  "https://XXXXXXXXXXXX.supabase.co",
  supabaseAnon: "PEGAR_ANON_KEY_PUBLICA",

  // Edge Functions. Normalmente no cambian.
  fnEmitir: "/functions/v1/deposito-emitir",
  fnMarcar: "/functions/v1/deposito-marcar",
  fnPanel:  "/functions/v1/deposito-panel",

  // Cada cuánto rota el QR en pantalla. El vencimiento real lo manda el
  // servidor (fichada.config.token_ttl_seg). Mantenerlos parecidos.
  periodoSeg: 30,
};
