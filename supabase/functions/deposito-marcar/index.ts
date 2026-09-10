// ============================================================================
// Edge Function: deposito-marcar
// Dos usos con el mismo token:
//   POST {token, email}         -> estado: qué puede fichar ahora (NO consume)
//   POST {token, email, tipo}   -> registra la marca (consume el token, jti único)
// La lógica vive en public.fichada_dep_estado / fichada_dep_marcar.
// verify_jwt=false a propósito: la autorización es el token firmado.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const TIPOS = ["entrada", "regreso", "comida_ini", "comida_fin", "salida", "fin"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  let body: { token?: string; email?: string; tipo?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body_invalido" }, 400);
  }

  const token = String(body?.token ?? "");
  const email = String(body?.email ?? "");
  const tipo = body?.tipo ? String(body.tipo) : "";
  if (!token || !email) return json({ error: "faltan_datos" }, 400);
  if (tipo && !TIPOS.includes(tipo)) return json({ error: "tipo_no_permitido" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = tipo
    ? await supabase.rpc("fichada_dep_marcar", { p_token: token, p_email: email, p_tipo: tipo })
    : await supabase.rpc("fichada_dep_estado", { p_token: token, p_email: email });

  if (error) {
    console.error("deposito-marcar:", error.message);
    return json({ error: "error_interno" }, 500);
  }
  return json(data);
});
