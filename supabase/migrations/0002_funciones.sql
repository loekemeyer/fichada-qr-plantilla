-- ============================================================================
-- Lógica en Postgres. Las Edge Functions son solo cáscara HTTP.
-- SECURITY DEFINER + search_path='' ; ejecutables solo por service_role.
-- El secreto de firma NUNCA sale al navegador.
-- ============================================================================

create or replace function fichada.b64url(p bytea)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(translate(encode(p, 'base64'), '+/', '-_'), '[=\n\r]', '', 'g')
$$;

-- ---------------------------------------------------------------------------
-- Valida firma y vencimiento. NO consume el token: eso lo hace fichada_dep_marcar.
-- ---------------------------------------------------------------------------
create or replace function fichada.validar_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_secret text; v_p text; v_sig text; v_calc text;
  v_json json; v_exp bigint; v_jti text; v_std text;
begin
  select token_secret into v_secret from fichada.config where id = 1;
  if v_secret is null then return jsonb_build_object('error','sin_config'); end if;
  if p_token is null or p_token = '' then return jsonb_build_object('error','token_invalido'); end if;

  v_p   := split_part(p_token, '.', 1);
  v_sig := split_part(p_token, '.', 2);
  if v_p = '' or v_sig = '' or split_part(p_token, '.', 3) <> '' then
    return jsonb_build_object('error','token_invalido');
  end if;

  v_calc := fichada.b64url(extensions.hmac(v_p, v_secret, 'sha256'));
  if v_sig <> v_calc then return jsonb_build_object('error','token_invalido'); end if;

  v_std := translate(v_p, '-_', '+/');
  v_std := v_std || repeat('=', (4 - (length(v_std) % 4)) % 4);
  begin
    v_json := convert_from(decode(v_std, 'base64'), 'utf8')::json;
  exception when others then
    return jsonb_build_object('error','token_invalido');
  end;

  v_exp := (v_json->>'exp')::bigint;
  v_jti := v_json->>'jti';
  if v_exp is null or v_jti is null then return jsonb_build_object('error','token_invalido'); end if;
  -- Esto es lo que hace inútil una foto vieja del QR.
  if v_exp < floor(extract(epoch from now())) then return jsonb_build_object('error','token_vencido'); end if;

  return jsonb_build_object('ok', true, 'jti', v_jti);
end;
$$;

-- ---------------------------------------------------------------------------
-- Máquina de estados. Entrar y volver NUNCA se eligen: se deducen.
-- Comen dentro del depósito, así que comida_ini/comida_fin no son salidas.
-- ---------------------------------------------------------------------------
create or replace function fichada.estado_de(p_correo text, p_fecha date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_tipo text; v_hora time; v_creado timestamptz; v_perm text[]; v_comida boolean;
begin
  select tipo, hora, creado_en into v_tipo, v_hora, v_creado
    from fichada.marcas
   where lower(correo) = lower(p_correo) and fecha = p_fecha
   order by hora desc, id desc
   limit 1;

  select exists (
    select 1 from fichada.marcas mi
     where lower(mi.correo) = lower(p_correo) and mi.fecha = p_fecha and mi.tipo = 'comida_ini'
       and not exists (
         select 1 from fichada.marcas mf
          where lower(mf.correo) = lower(p_correo) and mf.fecha = p_fecha
            and mf.tipo = 'comida_fin' and (mf.hora, mf.id) > (mi.hora, mi.id))
  ) into v_comida;

  if v_tipo is null then                       v_perm := array['entrada'];
  elsif v_tipo in ('salida','fin') then        v_perm := array['regreso'];
  elsif v_tipo = 'comida_ini' then             v_perm := array['comida_fin','salida','fin'];
  else                                         v_perm := array['comida_ini','salida','fin'];
  end if;

  return jsonb_build_object(
    'ultimo_tipo',   v_tipo,
    'ultima_hora',   to_char(v_hora, 'HH24:MI'),
    'permitidos',    to_jsonb(v_perm),
    'comida_abierta', v_comida,
    'seg_desde_ultima', case when v_creado is null then null
                             else floor(extract(epoch from (now() - v_creado)))::bigint end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Emitir token firmado. Solo la pantalla del depósito (clave de dispositivo).
-- ---------------------------------------------------------------------------
create or replace function public.fichada_dep_emitir_token(p_clave text)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_secret text; v_clave text; v_ttl int;
  v_jti text; v_exp bigint; v_payload text; v_b64 text; v_sig text;
begin
  select token_secret, clave_dispositivo, token_ttl_seg
    into v_secret, v_clave, v_ttl
    from fichada.config where id = 1;
  if v_secret is null then return json_build_object('error','sin_config'); end if;
  if p_clave is null or p_clave <> v_clave then
    return json_build_object('error','clave_invalida');
  end if;

  v_jti     := substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
  v_exp     := floor(extract(epoch from now())) + v_ttl;
  v_payload := '{"exp":' || v_exp::text || ',"jti":"' || v_jti || '"}';
  v_b64     := fichada.b64url(convert_to(v_payload, 'utf8'));
  v_sig     := fichada.b64url(extensions.hmac(v_b64, v_secret, 'sha256'));

  return json_build_object('token', v_b64 || '.' || v_sig, 'exp', v_exp);
end;
$$;

-- ---------------------------------------------------------------------------
-- Qué puede fichar esta persona ahora. Solo lee: no consume el token.
-- ---------------------------------------------------------------------------
create or replace function public.fichada_dep_estado(p_token text, p_email text)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_tok jsonb; v_est jsonb; v_email text := lower(trim(coalesce(p_email,'')));
  v_dep text; v_tz text; v_rebote int; v_fecha date;
  v_leg text; v_nom text; v_emp text;
begin
  if v_email = '' then return json_build_object('error','faltan_datos'); end if;

  v_tok := fichada.validar_token(p_token);
  if v_tok ? 'error' then return v_tok::json; end if;

  select deposito, zona_horaria, rebote_seg into v_dep, v_tz, v_rebote
    from fichada.config where id = 1;

  select legajo, nombre, empresa into v_leg, v_nom, v_emp
    from fichada.empleados where lower(correo) = v_email and activo;
  if v_nom is null then return json_build_object('error','no_habilitado'); end if;

  v_fecha := (now() at time zone v_tz)::date;
  v_est   := fichada.estado_de(v_email, v_fecha);

  return json_build_object(
    'ok', true,
    'deposito', v_dep,
    'nombre', v_nom, 'legajo', v_leg, 'empresa', v_emp,
    'permitidos',     v_est->'permitidos',
    'comida_abierta', v_est->'comida_abierta',
    'ultimo_tipo',    v_est->>'ultimo_tipo',
    'ultima_hora',    v_est->>'ultima_hora',
    'rebote', coalesce((v_est->>'seg_desde_ultima')::bigint < v_rebote, false),
    'rebote_seg', v_rebote
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Registrar la marca. Acá SÍ se consume el token (jti único).
-- ---------------------------------------------------------------------------
create or replace function public.fichada_dep_marcar(p_token text, p_email text, p_tipo text)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_tok jsonb; v_est jsonb; v_email text := lower(trim(coalesce(p_email,'')));
  v_tz text; v_rebote int; v_fecha date; v_hora time; v_id bigint;
  v_leg text; v_nom text; v_perm jsonb;
begin
  if v_email = '' or p_tipo is null then return json_build_object('error','faltan_datos'); end if;

  v_tok := fichada.validar_token(p_token);
  if v_tok ? 'error' then return v_tok::json; end if;

  select zona_horaria, rebote_seg into v_tz, v_rebote from fichada.config where id = 1;

  select legajo, nombre into v_leg, v_nom
    from fichada.empleados where lower(correo) = v_email and activo;
  if v_nom is null then return json_build_object('error','no_habilitado'); end if;

  v_fecha := (now() at time zone v_tz)::date;
  v_hora  := (now() at time zone v_tz)::time;
  v_est   := fichada.estado_de(v_email, v_fecha);

  -- Anti doble escaneo: dos marcas seguidas en segundos casi siempre son un error.
  if coalesce((v_est->>'seg_desde_ultima')::bigint, v_rebote + 1) < v_rebote then
    return json_build_object('error','rebote',
      'ultimo_tipo', v_est->>'ultimo_tipo', 'ultima_hora', v_est->>'ultima_hora');
  end if;

  v_perm := v_est->'permitidos';
  if not (v_perm @> to_jsonb(p_tipo)) then
    return json_build_object('error','tipo_no_permitido', 'permitidos', v_perm);
  end if;

  insert into fichada.marcas (correo, fecha, hora, tipo, origen, jti)
  values (v_email, v_fecha, v_hora, p_tipo, 'qr', v_tok->>'jti')
  on conflict do nothing
  returning id into v_id;

  if v_id is null then return json_build_object('error','token_usado'); end if;

  return json_build_object(
    'ok', true,
    'tipo', p_tipo,
    'hora', to_char(v_hora, 'HH24:MI'),
    'nombre', v_nom, 'legajo', v_leg,
    -- Se fue con la comida abierta: el día queda para que RR. HH. lo corrija.
    'comida_sin_cerrar', (p_tipo in ('salida','fin') and (v_est->>'comida_abierta')::boolean)
  );
end;
$$;

revoke all on function public.fichada_dep_emitir_token(text) from public;
revoke all on function public.fichada_dep_estado(text, text) from public;
revoke all on function public.fichada_dep_marcar(text, text, text) from public;
revoke execute on function public.fichada_dep_emitir_token(text) from anon, authenticated;
revoke execute on function public.fichada_dep_estado(text, text) from anon, authenticated;
revoke execute on function public.fichada_dep_marcar(text, text, text) from anon, authenticated;
grant execute on function public.fichada_dep_emitir_token(text) to service_role;
grant execute on function public.fichada_dep_estado(text, text) to service_role;
grant execute on function public.fichada_dep_marcar(text, text, text) to service_role;
