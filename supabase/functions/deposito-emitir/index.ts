// ============================================================================
// Edge Function: deposito-emitir
// Cáscara HTTP. La lógica (clave de dispositivo, filtro por IP, firma del token)
// vive en public.fichada_dep_emitir_token. El secreto NUNCA sale al navegador.
// verify_jwt=false a propósito: la autenticación es la clave de dispositivo.
//
// La IP la determina el SERVIDOR desde x-forwarded-for. Nunca se toma del body:
// si el cliente pudiera declarar su propia IP, el filtro no filtraría nada.
// NO confundir con fichada-qr-emitir-token, que es del sistema viejo.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-clave-dispositivo",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// El primer valor de x-forwarded-for es el cliente; el resto son los proxies.
function ipCliente(req: Request): string {
  const xff = req.headers.get("x-forwarded-for") ?? "";
  const primera = xff.split(",")[0]?.trim();
  return primera || (req.headers.get("x-real-ip") ?? "").trim();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  const ip = ipCliente(req);

  let clave = req.headers.get("x-clave-dispositivo") ?? "";
  if (!clave) {
    try {
      const b = await req.json();
      // Para descubrir la IP del depósito sin tener que activar el filtro.
      if (b?.whoami) return json({ ip });
      clave = b?.clave ?? "";
    } catch { /* body vacío */ }
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("fichada_dep_emitir_token", {
    p_clave: clave,
    p_ip: ip,
  });
  if (error) {
    console.error("fichada_dep_emitir_token:", error.message);
    return json({ error: "error_interno" }, 500);
  }
  const err = (data as { error?: string })?.error;
  const status = err === "clave_invalida" ? 401 : err === "ip_no_autorizada" ? 403 : 200;
  return json(data, status);
});
