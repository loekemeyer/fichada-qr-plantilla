// ============================================================================
// Edge Function: deposito-emitir
// Cáscara HTTP. La lógica (validar clave de dispositivo, firmar el token) vive
// en public.fichada_dep_emitir_token. El secreto NUNCA sale al navegador.
// verify_jwt=false a propósito: la autenticación es la clave de dispositivo.
// NO confundir con fichada-qr-emitir-token, que es del sistema viejo.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-clave-dispositivo",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  let clave = req.headers.get("x-clave-dispositivo") ?? "";
  if (!clave) {
    try {
      const b = await req.json();
      clave = b?.clave ?? "";
    } catch { /* body vacío */ }
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("fichada_dep_emitir_token", { p_clave: clave });
  if (error) {
    console.error("fichada_dep_emitir_token:", error.message);
    return json({ error: "error_interno" }, 500);
  }
  const status = (data as { error?: string })?.error === "clave_invalida" ? 401 : 200;
  return json(data, status);
});
