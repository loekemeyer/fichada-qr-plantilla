-- ============================================================================
-- Candado por IP: solo se emiten códigos QR desde la red del depósito.
--
-- Se aplica SOLO a emitir (la pantalla fija). Fichar NO se filtra: los operarios
-- escanean con sus celulares, muchos con datos móviles, y bloquearlos por IP
-- rompería la fichada sin ganar nada — el token firmado ya prueba que el código
-- salió de la pantalla.
--
-- El panel tampoco se filtra: es la válvula de escape. Si la IP queda mal
-- cargada y se corta la fichada, el filtro se apaga desde el panel, sin SQL.
-- ============================================================================

-- Toda IP que pide un código queda registrada, se acepte o se rechace. Con una
-- semana de esto se sabe si la IP del depósito es fija de verdad.
create table if not exists fichada.ips_vistas (
  ip            text primary key,
  primera_vez   timestamptz not null default now(),
  ultima_vez    timestamptz not null default now(),
  veces         bigint not null default 1,
  rechazadas    bigint not null default 0
);
alter table fichada.ips_vistas enable row level security;

-- La firma cambia de 1 a 2 parámetros: sacamos la vieja para no dejar dos.
drop function if exists public.fichada_dep_emitir_token(text);

create or replace function public.fichada_dep_emitir_token(p_clave text, p_ip text default null)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_secret text; v_clave text; v_ttl int; v_ip_ok text; v_permitida boolean;
  v_jti text; v_exp bigint; v_payload text; v_b64 text; v_sig text;
  v_ip text := nullif(btrim(coalesce(p_ip,'')), '');
begin
  select token_secret, clave_dispositivo, token_ttl_seg, ip_trabajo
    into v_secret, v_clave, v_ttl, v_ip_ok
    from fichada.config where id = 1;
  if v_secret is null then return json_build_object('error','sin_config'); end if;
  if p_clave is null or p_clave <> v_clave then
    return json_build_object('error','clave_invalida');
  end if;

  -- ip_trabajo vacío = filtro apagado. Acepta varias separadas por coma.
  v_permitida := (v_ip_ok is null or btrim(v_ip_ok) = '')
                 or (v_ip is not null
                     and v_ip = any(string_to_array(replace(v_ip_ok, ' ', ''), ',')));

  if v_ip is not null then
    insert into fichada.ips_vistas (ip, rechazadas)
    values (v_ip, case when v_permitida then 0 else 1 end)
    on conflict (ip) do update
      set ultima_vez = now(),
          veces      = fichada.ips_vistas.veces + 1,
          rechazadas = fichada.ips_vistas.rechazadas
                       + case when v_permitida then 0 else 1 end;
  end if;

  if not v_permitida then
    return json_build_object('error','ip_no_autorizada', 'ip', v_ip);
  end if;

  v_jti     := substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
  v_exp     := floor(extract(epoch from now())) + v_ttl;
  v_payload := '{"exp":' || v_exp::text || ',"jti":"' || v_jti || '"}';
  v_b64     := fichada.b64url(convert_to(v_payload, 'utf8'));
  v_sig     := fichada.b64url(extensions.hmac(v_b64, v_secret, 'sha256'));

  return json_build_object('token', v_b64 || '.' || v_sig, 'exp', v_exp);
end;
$$;

revoke all on function public.fichada_dep_emitir_token(text, text) from public;
revoke execute on function public.fichada_dep_emitir_token(text, text) from anon, authenticated;
grant execute on function public.fichada_dep_emitir_token(text, text) to service_role;
