-- ============================================================================
-- Panel de RR. HH. Una sola puerta con clave propia (clave_panel), distinta de
-- la clave de la pantalla del QR. Devuelve las marcas crudas: el cálculo de
-- horas y estados lo hace el navegador, con la misma regla que muestra en pantalla.
-- ============================================================================
create or replace function public.fichada_dep_panel(
  p_clave text, p_op text, p_payload jsonb default '{}'::jsonb
)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_clave text; v_tz text; v_fecha date; v_id bigint;
  v_correo text; v_legajo text; v_nombre text; v_empresa text; v_activo boolean;
  v_marca jsonb; v_n int := 0;
begin
  select clave_panel, zona_horaria into v_clave, v_tz from fichada.config where id = 1;
  if v_clave is null then return json_build_object('error','sin_config'); end if;
  if p_clave is null or p_clave <> v_clave then
    return json_build_object('error','clave_invalida');
  end if;

  -- ---------------------------------------------------------------- día
  if p_op = 'dia' then
    v_fecha := coalesce((p_payload->>'fecha')::date, (now() at time zone v_tz)::date);
    return json_build_object(
      'ok', true,
      'fecha', v_fecha,
      'hoy',   (now() at time zone v_tz)::date,
      'ahora', to_char(now() at time zone v_tz, 'HH24:MI'),
      'config', (select json_build_object(
                   'deposito', c.deposito,
                   'hora_entrada', to_char(c.hora_entrada,'HH24:MI'),
                   'hora_salida',  to_char(c.hora_salida,'HH24:MI'),
                   'comida_min', c.comida_min,
                   'tolerancia_min', c.tolerancia_min)
                 from fichada.config c where c.id = 1),
      'operarios', coalesce((
        select json_agg(x order by x.nombre)
        from (
          select e.legajo, e.nombre, e.correo, e.empresa, e.activo,
                 coalesce((
                   select json_agg(json_build_object(
                            'hora', to_char(m.hora,'HH24:MI'),
                            'tipo', m.tipo,
                            'origen', m.origen) order by m.hora, m.id)
                     from fichada.marcas m
                    where lower(m.correo) = lower(e.correo) and m.fecha = v_fecha
                 ), '[]'::json) as marcas
            from fichada.empleados e
           where e.activo
              or exists (select 1 from fichada.marcas m2
                          where lower(m2.correo) = lower(e.correo) and m2.fecha = v_fecha)
        ) x), '[]'::json)
    );

  -- --------------------------------------------------------- padrón completo
  elsif p_op = 'empleados' then
    return json_build_object('ok', true, 'operarios', coalesce((
      select json_agg(json_build_object(
               'id', e.id, 'legajo', e.legajo, 'nombre', e.nombre,
               'correo', e.correo, 'empresa', e.empresa, 'activo', e.activo)
             order by e.activo desc, e.nombre)
        from fichada.empleados e), '[]'::json));

  -- ------------------------------------------------------- alta / edición
  elsif p_op = 'guardar_empleado' then
    v_id      := nullif(p_payload->>'id','')::bigint;
    v_legajo  := trim(coalesce(p_payload->>'legajo',''));
    v_nombre  := trim(coalesce(p_payload->>'nombre',''));
    v_correo  := lower(trim(coalesce(p_payload->>'correo','')));
    v_empresa := trim(coalesce(p_payload->>'empresa',''));
    v_activo  := coalesce((p_payload->>'activo')::boolean, true);

    if v_nombre = '' or v_legajo = '' or v_empresa = '' then
      return json_build_object('error','faltan_datos');
    end if;
    if v_correo !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
      return json_build_object('error','correo_invalido');
    end if;
    if exists (select 1 from fichada.empleados e
                where lower(e.correo) = v_correo and (v_id is null or e.id <> v_id)) then
      return json_build_object('error','correo_repetido');
    end if;
    if exists (select 1 from fichada.empleados e
                where e.legajo = v_legajo and (v_id is null or e.id <> v_id)) then
      return json_build_object('error','legajo_repetido');
    end if;

    if v_id is null then
      insert into fichada.empleados (legajo, nombre, correo, empresa, activo)
      values (v_legajo, v_nombre, v_correo, v_empresa, v_activo)
      returning id into v_id;
    else
      update fichada.empleados
         set legajo = v_legajo, nombre = v_nombre, correo = v_correo,
             empresa = v_empresa, activo = v_activo, actualizado_en = now()
       where id = v_id;
      if not found then return json_build_object('error','no_existe'); end if;
    end if;
    return json_build_object('ok', true, 'id', v_id);

  -- ------------------------------------------------------------- baja / alta
  elsif p_op = 'baja_empleado' then
    v_id     := nullif(p_payload->>'id','')::bigint;
    v_activo := coalesce((p_payload->>'activo')::boolean, false);
    update fichada.empleados set activo = v_activo, actualizado_en = now() where id = v_id;
    if not found then return json_build_object('error','no_existe'); end if;
    return json_build_object('ok', true);

  -- ------------------------------------------- corrección manual de un día
  -- Reemplaza TODAS las marcas de esa persona ese día. Quedan como 'manual',
  -- que es lo que el panel muestra con el punto turquesa.
  elsif p_op = 'guardar_marcas' then
    v_fecha  := (p_payload->>'fecha')::date;
    v_correo := lower(trim(coalesce(p_payload->>'correo','')));
    if v_fecha is null or v_correo = '' then return json_build_object('error','faltan_datos'); end if;
    if not exists (select 1 from fichada.empleados where lower(correo) = v_correo) then
      return json_build_object('error','no_existe');
    end if;

    delete from fichada.marcas where lower(correo) = v_correo and fecha = v_fecha;
    for v_marca in select * from jsonb_array_elements(coalesce(p_payload->'marcas','[]'::jsonb)) loop
      if coalesce(v_marca->>'hora','') <> '' and coalesce(v_marca->>'tipo','') <> '' then
        insert into fichada.marcas (correo, fecha, hora, tipo, origen, nota)
        values (v_correo, v_fecha, (v_marca->>'hora')::time, v_marca->>'tipo',
                'manual', nullif(p_payload->>'nota',''));
        v_n := v_n + 1;
      end if;
    end loop;
    return json_build_object('ok', true, 'marcas', v_n);
  end if;

  return json_build_object('error','op_desconocida');
end;
$$;

revoke all on function public.fichada_dep_panel(text, text, jsonb) from public;
revoke execute on function public.fichada_dep_panel(text, text, jsonb) from anon, authenticated;
grant execute on function public.fichada_dep_panel(text, text, jsonb) to service_role;
