// ============================================================================
// Edge Function: deposito-panel
// Puerta única del panel de RR. HH. POST {clave, op, payload}.
// La clave es clave_panel, distinta de la clave de la pantalla del QR: si se
// filtra la del dispositivo, el panel sigue cerrado.
// ops: dia | empleados | guardar_empleado | baja_empleado | guardar_marcas
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPS = ["dia", "empleados", "guardar_empleado", "baja_empleado", "guardar_marcas",
             "clave_dispositivo", "cambiar_clave"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  let body: { clave?: string; op?: string; payload?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body_invalido" }, 400);
  }

  const clave = String(body?.clave ?? "");
  const op = String(body?.op ?? "");
  if (!clave) return json({ error: "clave_invalida" }, 401);
  if (!OPS.includes(op)) return json({ error: "op_desconocida" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("fichada_dep_panel", {
    p_clave: clave,
    p_op: op,
    p_payload: body?.payload ?? {},
  });

  if (error) {
    console.error("deposito-panel:", error.message);
    return json({ error: "error_interno" }, 500);
  }
  const status = (data as { error?: string })?.error === "clave_invalida" ? 401 : 200;
  return json(data, status);
});
