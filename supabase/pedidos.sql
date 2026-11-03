-- =====================================================================
--  VISOR 3D RUMM — pedidos nuevos desde pedido.html
--
--  Ejecutar DESPUÉS de esquema.sql (SQL Editor › New query › Run).
--  Se puede volver a ejecutar sin romper nada.
--
--  El cliente rellena pedido.html; se crea a la vez el pedido (número
--  AAAA-NNNN) y su enlace privado ver.html?c=TOKEN, que queda esperando
--  hasta que el estudio publica el primer diseño.
-- =====================================================================

create table if not exists public.pedidos (
  id          bigint generated always as identity primary key,
  numero      text not null unique,
  token       text not null references public.clientes(token) on delete cascade,
  nombre      text not null,
  email       text not null,
  telefono    text not null default '',
  empresa     text not null default '',
  disciplina  text not null default '',
  colores     text not null default '',
  prendas     jsonb not null default '[]'::jsonb,
  descripcion text not null default '' check (char_length(descripcion) <= 5000),
  adjuntos    jsonb not null default '[]'::jsonb,
  estado      text not null default 'nuevo'
              check (estado in ('nuevo','en_diseno','enviado','aprobado','cancelado')),
  creado      timestamptz not null default now()
);
create index if not exists pedidos_creado on public.pedidos (creado);
create index if not exists pedidos_token  on public.pedidos (token);

alter table public.pedidos enable row level security;

drop policy if exists estudio_pedidos on public.pedidos;
create policy estudio_pedidos on public.pedidos
  for all to authenticated using (public.es_estudio()) with check (public.es_estudio());

-- ---------------------------------------------------------------------
--  El cliente crea el pedido. Devuelve el token de su enlace y el número.
-- ---------------------------------------------------------------------

create or replace function public.nuevo_pedido(
  p_nombre text, p_email text, p_telefono text, p_empresa text,
  p_disciplina text, p_colores text, p_prendas jsonb, p_descripcion text
) returns table (token text, numero text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_nombre  text := left(btrim(coalesce(p_nombre,'')), 80);
  v_email   text := lower(left(btrim(coalesce(p_email,'')), 120));
  v_empresa text := left(btrim(coalesce(p_empresa,'')), 120);
  v_prendas jsonb := coalesce(p_prendas, '[]'::jsonb);
  v_token   text;
  v_numero  text;
  v_anio    text := to_char(now() at time zone 'Europe/Madrid', 'YYYY');
  v_n       int;
begin
  if v_nombre = '' then raise exception 'Falta el nombre'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'El email no es válido'; end if;
  if jsonb_typeof(v_prendas) <> 'array' or jsonb_array_length(v_prendas) > 30 then
    raise exception 'Prendas no válidas';
  end if;

  -- Freno al spam: el formulario es público
  if (select count(*) from pedidos where creado > now() - interval '1 hour') >= 30 then
    raise exception 'Hay muchos pedidos ahora mismo. Inténtalo dentro de un rato.';
  end if;
  if (select count(*) from pedidos where email = v_email and creado > now() - interval '1 day') >= 5 then
    raise exception 'Ya has enviado varios pedidos hoy. Escríbenos si necesitas algo más.';
  end if;

  -- Numeración por año, sin huecos ni duplicados aunque lleguen dos a la vez
  perform pg_advisory_xact_lock(724001);
  select coalesce(max(split_part(p.numero, '-', 2)::int), 0) + 1 into v_n
    from pedidos p where p.numero like v_anio || '-%';
  v_numero := v_anio || '-' || lpad(v_n::text, 4, '0');

  loop
    v_token := substr(md5(gen_random_uuid()::text), 1, 12);
    exit when not exists (select 1 from clientes c where c.token = v_token);
  end loop;

  insert into clientes (token, nombre)
  values (v_token, case when v_empresa <> '' then v_empresa else v_nombre end);

  insert into pedidos (numero, token, nombre, email, telefono, empresa,
                       disciplina, colores, prendas, descripcion)
  values (v_numero, v_token, v_nombre, v_email,
          left(btrim(coalesce(p_telefono,'')), 40), v_empresa,
          left(coalesce(p_disciplina,''), 300), left(coalesce(p_colores,''), 600),
          v_prendas, left(coalesce(p_descripcion,''), 5000));

  return query select v_token, v_numero;
end $$;

-- Los archivos se suben después de crear el pedido (necesitan su carpeta).
-- Solo se pueden añadir una vez y en los 30 minutos siguientes.
create or replace function public.pedido_adjuntos(p_token text, p_adjuntos jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  adj jsonb := coalesce(p_adjuntos, '[]'::jsonb);
begin
  if jsonb_typeof(adj) <> 'array' or jsonb_array_length(adj) > 10 then
    raise exception 'Adjuntos no válidos';
  end if;
  if exists (select 1 from jsonb_array_elements(adj) a
             where coalesce(a->>'path','') not like p_token || '/pedido/%') then
    raise exception 'Adjuntos no válidos';
  end if;
  update pedidos set adjuntos = adj
   where token = p_token
     and adjuntos = '[]'::jsonb
     and creado > now() - interval '30 minutes';
end $$;

-- Lo que ve el cliente en su enlace mientras preparamos el diseño
create or replace function public.pedido_de(p_token text)
returns table (numero text, nombre text, empresa text, estado text, creado timestamptz)
language sql stable security definer set search_path = public as $$
  select numero, nombre, empresa, estado, creado
    from pedidos where token = p_token
   order by creado desc limit 1
$$;

revoke all on function public.nuevo_pedido(text,text,text,text,text,text,jsonb,text) from public;
revoke all on function public.pedido_adjuntos(text,jsonb) from public;
revoke all on function public.pedido_de(text) from public;
grant execute on function public.nuevo_pedido(text,text,text,text,text,text,jsonb,text) to anon, authenticated;
grant execute on function public.pedido_adjuntos(text,jsonb) to anon, authenticated;
grant execute on function public.pedido_de(text) to anon, authenticated;

-- ---------------------------------------------------------------------
--  Cuando el cliente aprueba un diseño, el pedido pasa a «aprobado»
-- ---------------------------------------------------------------------

create or replace function public.pedido_aprobado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'aprobado' then
    update pedidos set estado = 'aprobado'
     where token = new.token and estado in ('nuevo','en_diseno','enviado');
  end if;
  return new;
end $$;

drop trigger if exists pedido_aprobado on public.mensajes;
create trigger pedido_aprobado after insert on public.mensajes
  for each row execute function public.pedido_aprobado();

-- ---------------------------------------------------------------------
--  Aviso por correo de cada pedido nuevo (usa los ajustes de esquema.sql)
-- ---------------------------------------------------------------------

create or replace function public.avisar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  clave_resend text;
  destino      text;
  visor        text;
  prendas      text;
  cuerpo       text;
begin
  select valor into clave_resend from ajustes where clave = 'resend_key';
  select valor into destino      from ajustes where clave = 'aviso_email';
  select valor into visor        from ajustes where clave = 'visor_url';
  if coalesce(clave_resend,'') = '' or coalesce(destino,'') = '' then return new; end if;

  select string_agg(coalesce(p->>'nombre', p->>'codigo')
                    || case when coalesce(p->>'cantidad','') <> '' then ' × ' || (p->>'cantidad') else '' end, ', ')
    into prendas from jsonb_array_elements(new.prendas) p;

  cuerpo := '<div style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5">'
         || '<p style="color:#8A8A85;font-size:11px;letter-spacing:.12em;text-transform:uppercase">Pedido '
         || new.numero || '</p>'
         || '<p><b>' || html_esc(new.nombre) || '</b>'
         || case when new.empresa <> '' then ' · ' || html_esc(new.empresa) else '' end || '<br>'
         || html_esc(new.email)
         || case when new.telefono <> '' then ' · ' || html_esc(new.telefono) else '' end || '</p>'
         || case when new.disciplina <> '' then '<p><b>Disciplina:</b> ' || html_esc(new.disciplina) || '</p>' else '' end
         || case when coalesce(prendas,'') <> '' then '<p><b>Prendas:</b> ' || html_esc(prendas) || '</p>' else '' end
         || case when new.colores <> '' then '<p><b>Colores:</b> ' || html_esc(new.colores) || '</p>' else '' end
         || case when new.descripcion <> '' then '<p>' || html_esc(new.descripcion) || '</p>' else '' end
         || case when coalesce(visor,'') <> ''
                 then '<p><a href="' || visor || 'index.html#pedidos">Abrir pedidos</a></p>' else '' end
         || '</div>';

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || clave_resend,
                                  'Content-Type',  'application/json'),
    body    := jsonb_build_object('from',     'Visor RUMM <onboarding@resend.dev>',
                                  'to',       jsonb_build_array(destino),
                                  'reply_to', new.email,
                                  'subject',  'Pedido ' || new.numero || ' · '
                                              || case when new.empresa <> '' then new.empresa else new.nombre end,
                                  'html',     cuerpo)
  );
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists avisar_pedido on public.pedidos;
create trigger avisar_pedido after insert on public.pedidos
  for each row execute function public.avisar_pedido();
