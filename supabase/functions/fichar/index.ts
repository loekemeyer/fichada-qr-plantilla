// ============================================================================
// Edge Function: fichar
// Cáscara HTTP + CORS. La lógica (firma + vencimiento + correo habilitado +
// 1/día + registro) vive en la función SQL public.fichada_fichar (solo
// service_role). El vencimiento se chequea del lado del servidor: una FOTO de un
// código VENCIDO no sirve.
// Deploy con --no-verify-jwt: la autorización es el propio token firmado.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

  let body: { token?: string; email?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body_invalido" }, 400);
  }
  const token = String(body?.token ?? "");
  const email = String(body?.email ?? "");
  if (!token || !email) return json({ error: "faltan_datos" }, 400);

  // ---------------------------------------------------------------------------
  // CAPA OPCIONAL "solo desde la fábrica" (por IP pública). Desactivada por
  // defecto. Para activarla: cargar config.ip_trabajo con la IP pública FIJA de
  // la empresa y descomentar. Ojo: se saltea con VPN/datos móviles, va como
  // complemento del QR rotativo, no como única defensa. Requiere IP fija sin CGNAT.
  //
  // const ipCliente = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  // (comparar contra config.ip_trabajo del lado servidor antes de fichar)
  // ---------------------------------------------------------------------------

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("fichada_fichar", {
    p_token: token,
    p_email: email,
  });
  if (error) return json({ error: "error_interno", detalle: error.message }, 500);

  return json(data);
});
