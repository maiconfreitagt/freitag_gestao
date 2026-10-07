-- RASCUNHO DE MIGRAÇÃO — NÃO APLICAR NA PRODUÇÃO AINDA.
-- Não vincula nem altera agendamentos, profissionais ou financeiro existentes.
-- Antes de aplicar, mapear a conta atual e preparar a migração segura dos dados.

begin;

create table public.empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(trim(nome)) between 2 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  telefone text,
  whatsapp text,
  endereco text,
  google_maps_url text,
  logo_url text,
  cor_destaque text not null default '#b5f52b' check (cor_destaque ~ '^#[0-9A-Fa-f]{6}$'),
  publicada boolean not null default false,
  criada_em timestamptz not null default now()
);

create table public.empresa_membros (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  papel text not null check (papel in ('dono', 'funcionario')),
  criado_em timestamptz not null default now(),
  primary key (empresa_id, usuario_id)
);

-- Na primeira versão, cada conta de dono administra um comércio.
create unique index empresa_um_dono_por_conta
  on public.empresa_membros(usuario_id) where papel = 'dono';

create table public.assinaturas (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  status text not null check (status in ('teste', 'ativa', 'atrasada', 'suspensa', 'cancelada')),
  teste_ate timestamptz,
  atualizada_em timestamptz not null default now()
);

-- Esta lista é preenchida somente por um administrador de banco confiável.
-- O identificador do dono da plataforma será vinculado em uma etapa posterior.
create table public.administradores_plataforma (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);

alter table public.empresas enable row level security;
alter table public.empresa_membros enable row level security;
alter table public.assinaturas enable row level security;
alter table public.administradores_plataforma enable row level security;

create or replace function public.empresa_usuario_eh_membro(p_empresa_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public set row_security = off
as $$
  select exists (
    select 1 from public.empresa_membros m
    where m.empresa_id = p_empresa_id and m.usuario_id = (select auth.uid())
  );
$$;

create or replace function public.empresa_usuario_eh_dono(p_empresa_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public set row_security = off
as $$
  select exists (
    select 1 from public.empresa_membros m
    where m.empresa_id = p_empresa_id
      and m.usuario_id = (select auth.uid()) and m.papel = 'dono'
  );
$$;

create or replace function public.usuario_eh_admin_plataforma()
returns boolean language sql stable security definer
set search_path = pg_catalog, public set row_security = off
as $$
  select exists (
    select 1 from public.administradores_plataforma a
    where a.usuario_id = (select auth.uid())
  );
$$;

create or replace function public.empresa_publica_ativa(p_empresa_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public set row_security = off
as $$
  select exists (
    select 1 from public.empresas e
    join public.assinaturas s on s.empresa_id = e.id
    where e.id = p_empresa_id and e.publicada = true
      and (s.status = 'ativa' or (s.status = 'teste' and s.teste_ate > now()))
  );
$$;

revoke all on function public.empresa_usuario_eh_membro(uuid) from public;
revoke all on function public.empresa_usuario_eh_dono(uuid) from public;
revoke all on function public.usuario_eh_admin_plataforma() from public;
revoke all on function public.empresa_publica_ativa(uuid) from public;
grant execute on function public.empresa_usuario_eh_membro(uuid) to anon, authenticated;
grant execute on function public.empresa_usuario_eh_dono(uuid) to anon, authenticated;
grant execute on function public.usuario_eh_admin_plataforma() to anon, authenticated;
grant execute on function public.empresa_publica_ativa(uuid) to anon, authenticated;

create policy empresas_ler_propria_publica_ou_admin
  on public.empresas for select to anon, authenticated
  using (public.empresa_usuario_eh_membro(id)
      or public.empresa_publica_ativa(id)
      or public.usuario_eh_admin_plataforma());

create policy empresas_dono_atualizar
  on public.empresas for update to authenticated
  using (public.empresa_usuario_eh_dono(id))
  with check (public.empresa_usuario_eh_dono(id));

create policy membros_dono_proprio_ou_admin_ler
  on public.empresa_membros for select to authenticated
  using (usuario_id = (select auth.uid())
      or public.empresa_usuario_eh_dono(empresa_id)
      or public.usuario_eh_admin_plataforma());

create policy assinatura_dono_ou_admin_ler
  on public.assinaturas for select to authenticated
  using (public.empresa_usuario_eh_dono(empresa_id)
      or public.usuario_eh_admin_plataforma());

-- O cliente atualiza campos de apresentação, sem poder editar a assinatura.
revoke all on public.empresas, public.empresa_membros, public.assinaturas,
  public.administradores_plataforma from anon, authenticated;
grant select on public.empresas to anon, authenticated;
grant update (nome, slug, telefone, whatsapp, endereco, google_maps_url,
  logo_url, cor_destaque, publicada) on public.empresas to authenticated;
grant select on public.empresa_membros, public.assinaturas to authenticated;

create or replace function public.criar_empresa(p_nome text, p_slug text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public set row_security = off
as $$
declare
  v_usuario uuid := auth.uid();
  v_empresa uuid;
  v_slug text := lower(trim(coalesce(p_slug, '')));
begin
  if v_usuario is null then raise exception 'LOGIN_NECESSARIO'; end if;
  if char_length(trim(coalesce(p_nome, ''))) not between 2 and 100 then
    raise exception 'NOME_EMPRESA_INVALIDO';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'LINK_EMPRESA_INVALIDO';
  end if;

  insert into public.empresas (nome, slug)
  values (trim(p_nome), v_slug) returning id into v_empresa;
  insert into public.empresa_membros (empresa_id, usuario_id, papel)
  values (v_empresa, v_usuario, 'dono');
  insert into public.assinaturas (empresa_id, status, teste_ate)
  values (v_empresa, 'teste', now() + interval '14 days');
  return v_empresa;
end;
$$;
revoke all on function public.criar_empresa(text, text) from public, anon;
grant execute on function public.criar_empresa(text, text) to authenticated;

-- Somente o administrador Freitag pode marcar pagamento, atraso ou suspensão.
create or replace function public.definir_status_assinatura(
  p_empresa_id uuid, p_status text, p_teste_ate timestamptz default null
)
returns void language plpgsql security definer
set search_path = pg_catalog, public set row_security = off
as $$
begin
  if auth.uid() is null or not public.usuario_eh_admin_plataforma() then
    raise exception 'SEM_PERMISSAO_ADMIN';
  end if;
  if p_status not in ('teste', 'ativa', 'atrasada', 'suspensa', 'cancelada') then
    raise exception 'STATUS_ASSINATURA_INVALIDO';
  end if;
  update public.assinaturas
     set status = p_status,
         teste_ate = case when p_status = 'teste' then p_teste_ate else null end,
         atualizada_em = now()
   where empresa_id = p_empresa_id;
  if not found then raise exception 'EMPRESA_NAO_ENCONTRADA'; end if;
end;
$$;
revoke all on function public.definir_status_assinatura(uuid, text, timestamptz) from public, anon;
grant execute on function public.definir_status_assinatura(uuid, text, timestamptz) to authenticated;

commit;
