// ============================================================================
// Config POR EMPRESA. Copiá este archivo a `config.js` y completá los valores.
// `config.js` está en .gitignore: nunca se sube al repo.
//
// El anon key es PÚBLICO por diseño (va en el navegador). El secreto de firma y
// la clave de dispositivo NO van acá: viven solo en Supabase.
// ============================================================================
window.FICHADA_CFG = {
  // Nombre visible de la empresa (aparece en la pantalla y en fichar).
  empresa: "Tu Empresa",

  // Proyecto Supabase de ESTA empresa.
  supabaseUrl: "https://XXXXXXXXXXXX.supabase.co",
  supabaseAnon: "PEGAR_ANON_KEY_PUBLICA",

  // Endpoints de las Edge Functions (normalmente no cambian).
  fnEmitir: "/functions/v1/emitir-token",
  fnFichar: "/functions/v1/fichar",

  // Segundos que se muestra cada QR antes de rotar. El vencimiento real (TTL)
  // se controla en Supabase (config.token_ttl_seg). Manténlos parecidos.
  periodoSeg: 30,
};
