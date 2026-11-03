-- =====================================================================
--  VISOR 3D RUMM — revisiones de diseños
--
--  Pegar entero en Supabase › SQL Editor › New query › Run.
--  Se puede volver a ejecutar sin romper nada.
--
--  ANTES DE EJECUTAR cambia los tres valores marcados con  <<<
--  al final del archivo (tu correo, la clave de Resend y la URL del visor).
-- =====================================================================

create extension if not exists pg_net;

-- ---------------------------------------------------------------------
--  Tablas
-- ---------------------------------------------------------------------

-- Clientes con enlace publicado. El visor interno los da de alta al publicar.
create table if not exists public.clientes (
  token  text primary key check (token ~ '^[a-z0-9]{12}$'),
  nombre text not null,
  creado timestamptz not null default now()
);

-- Todo el historial de un diseño: comentarios, versiones, decisiones.
--   tipo = 'comentario'  el cliente pide un cambio        (estado pendiente/aceptado/rechazado)
--          'aprobado'    el cliente aprueba una versión
--          'version'     el estudio publica una versión    (adjunto: la vista previa)
--          'respuesta'   el estudio contesta
create table if not exists public.mensajes (
  id            bigint generated always as identity primary key,
  token         text not null references public.clientes(token) on delete cascade,
  diseno        text not null,
  diseno_titulo text not null default '',
  version       int  not null default 1,
  autor         text not null check (autor in ('cliente','estudio')),
  nombre        text not null default '',
  tipo          text not null check (tipo in ('comentario','aprobado','version','respuesta')),
  texto         text not null default '' check (char_length(texto) <= 5000),
  adjuntos      jsonb not null default '[]'::jsonb,
  estado        text check (estado in ('pendiente','aceptado','rechazado')),
  motivo        text,
  resuelto      timestamptz,
  creado        timestamptz not null default now()
);
create index if not exists mensajes_hilo on public.mensajes (token, diseno, creado);
create index if not exists mensajes_pendientes on public.mensajes (estado) where estado = 'pendiente';

-- Correos del estudio con acceso completo. Solo quien esté aquí puede
-- leer y gestionar todo, aunque alguien llegue a crearse una cuenta.
create table if not exists public.equipo (
  email text primary key
);

-- Ajustes privados del aviso por correo. Sin políticas: nadie los lee desde fuera.
create table if not exists public.ajustes (
  clave text primary key,
  valor text not null
);

alter table public.clientes enable row level security;
alter table public.mensajes enable row level security;
alter table public.equipo   enable row level security;
alter table public.ajustes  enable row level security;

-- ---------------------------------------------------------------------
--  Funciones auxiliares
-- ---------------------------------------------------------------------

create or replace function public.es_estudio() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from equipo where lower(email) = lower(coalesce(auth.jwt()->>'email','')))
$$;

create or replace function public.token_valido(t text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from clientes where token = t)
$$;

-- ---------------------------------------------------------------------
--  Acceso del estudio: todo, siempre que su correo esté en «equipo»
-- ---------------------------------------------------------------------

drop policy if exists estudio_clientes on public.clientes;
create policy estudio_clientes on public.clientes
  for all to authenticated using (public.es_estudio()) with check (public.es_estudio());

drop policy if exists estudio_mensajes on public.mensajes;
create policy estudio_mensajes on public.mensajes
  for all to authenticated using (public.es_estudio()) with check (public.es_estudio());

-- ---------------------------------------------------------------------
--  Acceso del cliente: solo con su token y solo por estas dos funciones.
--  Las tablas no se pueden leer directamente.
-- ---------------------------------------------------------------------

create or replace function public.hilo(p_token text)
returns setof public.mensajes
language sql stable security definer set search_path = public as $$
  select * from mensajes where token = p_token order by creado, id
$$;

create or replace function public.enviar(
  p_token text, p_diseno text, p_titulo text, p_version int,
  p_nombre text, p_texto text, p_tipo text, p_adjuntos jsonb
) returns public.mensajes
language plpgsql security definer set search_path = public as $$
declare
  adj jsonb := coalesce(p_adjuntos, '[]'::jsonb);
  m   mensajes;
begin
  if not token_valido(p_token) then
    raise exception 'Enlace no válido';
  end if;
  if p_tipo not in ('comentario','aprobado') then
    raise exception 'Tipo de mensaje no válido';
  end if;
  if jsonb_typeof(adj) <> 'array' or jsonb_array_length(adj) > 10 then
    raise exception 'Adjuntos no válidos';
  end if;
  -- Los adjuntos tienen que estar en la carpeta de este cliente
  if exists (select 1 from jsonb_array_elements(adj) a
             where coalesce(a->>'path','') not like p_token || '/%') then
    raise exception 'Adjuntos no válidos';
  end if;
  if p_tipo = 'comentario' and btrim(coalesce(p_texto,'')) = '' and jsonb_array_length(adj) = 0 then
    raise exception 'El comentario está vacío';
  end if;

  insert into mensajes (token, diseno, diseno_titulo, version, autor, nombre, tipo, texto, adjuntos, estado)
  values (p_token,
          left(coalesce(p_diseno,''), 60),
          left(coalesce(p_titulo,''), 200),
          greatest(coalesce(p_version,1), 1),
          'cliente',
          left(btrim(coalesce(p_nombre,'')), 80),
          p_tipo,
          left(coalesce(p_texto,''), 5000),
          adj,
          case when p_tipo = 'comentario' then 'pendiente' end)
  returning * into m;
  return m;
end $$;

revoke all on function public.hilo(text) from public;
revoke all on function public.enviar(text,text,text,int,text,text,text,jsonb) from public;
grant execute on function public.hilo(text) to anon, authenticated;
grant execute on function public.enviar(text,text,text,int,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.token_valido(text) to anon, authenticated;
grant execute on function public.es_estudio() to anon, authenticated;

-- ---------------------------------------------------------------------
--  Adjuntos: bucket público de lectura (como el repositorio de GitHub:
--  solo entra quien conoce la ruta, que lleva el token del cliente).
--  Subir: el cliente solo dentro de su carpeta; el estudio en cualquiera.
--  Nadie puede listar el bucket.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('adjuntos', 'adjuntos', true, 26214400)
on conflict (id) do update set public = true, file_size_limit = 26214400;

drop policy if exists adjuntos_cliente on storage.objects;
create policy adjuntos_cliente on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'adjuntos' and public.token_valido((storage.foldername(name))[1]));

drop policy if exists adjuntos_estudio on storage.objects;
create policy adjuntos_estudio on storage.objects
  for all to authenticated
  using (bucket_id = 'adjuntos' and public.es_estudio())
  with check (bucket_id = 'adjuntos' and public.es_estudio());

-- ---------------------------------------------------------------------
--  Aviso por correo con Resend cuando el cliente escribe
-- ---------------------------------------------------------------------

create or replace function public.html_esc(t text) returns text
language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t,''), '&','&amp;'), '<','&lt;'), '>','&gt;'), E'\n', '<br>')
$$;

create or replace function public.avisar_mensaje() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  clave_resend text;
  destino      text;
  visor        text;
  cliente      text;
  asunto       text;
  cuerpo       text;
  n_adj        int := jsonb_array_length(new.adjuntos);
begin
  if new.autor <> 'cliente' then return new; end if;

  select valor into clave_resend from ajustes where clave = 'resend_key';
  select valor into destino      from ajustes where clave = 'aviso_email';
  select valor into visor        from ajustes where clave = 'visor_url';
  if coalesce(clave_resend,'') = '' or coalesce(destino,'') = '' then return new; end if;

  select nombre into cliente from clientes where token = new.token;

  asunto := case when new.tipo = 'aprobado' then 'Aprobado · ' else 'Comentario · ' end
            || coalesce(cliente,'') || ' · ' || new.diseno_titulo || ' v' || new.version;

  cuerpo := '<div style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5">'
         || '<p style="color:#8A8A85;font-size:11px;letter-spacing:.12em;text-transform:uppercase">'
         || html_esc(coalesce(cliente,'')) || ' · ' || html_esc(new.diseno_titulo) || ' · v' || new.version || '</p>'
         || case when new.tipo = 'aprobado'
                 then '<p><b>' || html_esc(coalesce(nullif(new.nombre,''),'El cliente')) || ' ha aprobado la versión ' || new.version || '.</b></p>'
                 else '<p><b>' || html_esc(coalesce(nullif(new.nombre,''),'El cliente')) || ' pide cambios:</b></p>' end
         || case when new.texto <> '' then '<p>' || html_esc(new.texto) || '</p>' else '' end
         || case when n_adj > 0 then '<p style="color:#8A8A85">' || n_adj || ' archivo(s) adjunto(s)</p>' else '' end
         || case when coalesce(visor,'') <> ''
                 then '<p><a href="' || visor || 'index.html#revisiones">Abrir revisiones</a> · '
                   || '<a href="' || visor || 'ver.html?c=' || new.token || '">Ver lo que ve el cliente</a></p>'
                 else '' end
         || '</div>';

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || clave_resend,
                                  'Content-Type',  'application/json'),
    body    := jsonb_build_object('from',    'Visor RUMM <onboarding@resend.dev>',
                                  'to',      jsonb_build_array(destino),
                                  'subject', asunto,
                                  'html',    cuerpo)
  );
  return new;
exception when others then
  -- Si el aviso falla, el comentario se guarda igual
  return new;
end $$;

drop trigger if exists avisar_mensaje on public.mensajes;
create trigger avisar_mensaje after insert on public.mensajes
  for each row execute function public.avisar_mensaje();

-- ---------------------------------------------------------------------
--  TUS DATOS  <<<  cambia estos tres valores antes de ejecutar
-- ---------------------------------------------------------------------

insert into public.equipo (email) values
  ('tu-correo@gobik.com')                                   -- <<< el correo con el que entrarás al visor
on conflict do nothing;

insert into public.ajustes (clave, valor) values
  ('aviso_email', 'tu-correo@gobik.com'),                   -- <<< a dónde llegan los avisos (el de tu cuenta de Resend)
  ('resend_key',  're_XXXXXXXXXXXXXXXX'),                   -- <<< clave de API de Resend
  ('visor_url',   'https://dasogu92.github.io/VISOR3D/')
on conflict (clave) do update set valor = excluded.valor;
