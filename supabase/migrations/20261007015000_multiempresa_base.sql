-- RASCUNHO DE MIGRAÇÃO — NÃO APLICAR NA PRODUÇÃO AINDA.
-- Esta base não vincula nem altera agendamentos, profissionais ou financeiro existentes.
-- Antes de aplicar, mapear a conta administradora atual e preparar a migração dos dados.

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
-- A estrutura poderá ser ampliada para múltiplas unidades depois.
create unique index empresa_um_dono_por_conta
  on public.empresa_membros(usuario_id) where papel = 'dono';

create table public.assinaturas (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  status text not null check (status in ('teste', 'ativa', 'atrasada', 'suspensa', 'cancelada')),
  teste_ate timestamptz,
  atualizada_em timestamptz not null default now()
);

alter table public.empresas enable row level security;
alter table public.empresa_membros enable row level security;
alter table public.assinaturas enable row level security;

create or replace function public.empresa_usuario_eh_membro(p_empresa_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
set row_security = off
as $$
  select exists (
    select 1 from public.empresa_membros m
    where m.empresa_id = p_empresa_id
      and m.usuario_id = (select auth.uid())
  );
$$;

create or replace function public.empresa_usuario_eh_dono(p_empresa_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
set row_security = off
as $$
  select exists (
    select 1 from public.empresa_membros m
    where m.empresa_id = p_empresa_id
      and m.usuario_id = (select auth.uid())
      and m.papel = 'dono'
  );
$$;

create or replace function public.empresa_publica_ativa(p_empresa_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
set row_security = off
as $$
  select exists (
    select 1
    from public.empresas e
    join public.assinaturas s on s.empresa_id = e.id
    where e.id = p_empresa_id
      and e.publicada = true
      and (
        s.status = 'ativa'
        or (s.status = 'teste' and s.teste_ate > now())
      )
  );
$$;

revoke all on function public.empresa_usuario_eh_membro(uuid) from public;
revoke all on function public.empresa_usuario_eh_dono(uuid) from public;
revoke all on function public.empresa_publica_ativa(uuid) from public;
grant execute on function public.empresa_usuario_eh_membro(uuid) to anon, authenticated;
grant execute on function public.empresa_usuario_eh_dono(uuid) to anon, authenticated;
grant execute on function public.empresa_publica_ativa(uuid) to anon, authenticated;

create policy empresas_ler_propria_ou_publica_ativa
  on public.empresas for select to anon, authenticated
  using (public.empresa_usuario_eh_membro(id) or public.empresa_publica_ativa(id));

create policy empresas_dono_atualizar
  on public.empresas for update to authenticated
  using (public.empresa_usuario_eh_dono(id))
  with check (public.empresa_usuario_eh_dono(id));

create policy membros_dono_ou_proprio_usuario_ler
  on public.empresa_membros for select to authenticated
  using (usuario_id = (select auth.uid()) or public.empresa_usuario_eh_dono(empresa_id));

create policy assinatura_dono_ler
  on public.assinaturas for select to authenticated
  using (public.empresa_usuario_eh_dono(empresa_id));

-- O cliente pode ler os dados públicos e atualizar somente campos de apresentação.
-- Não recebe INSERT direto, nem acesso de escrita à tabela de assinaturas.
revoke all on public.empresas, public.empresa_membros, public.assinaturas from anon, authenticated;
grant select on public.empresas to anon, authenticated;
grant update (nome, slug, telefone, whatsapp, endereco, google_maps_url, logo_url, cor_destaque, publicada)
  on public.empresas to authenticated;
grant select on public.empresa_membros, public.assinaturas to authenticated;

create or replace function public.criar_empresa(p_nome text, p_slug text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_usuario uuid := auth.uid();
  v_empresa uuid;
  v_slug text := lower(trim(p_slug));
begin
  if v_usuario is null then
    raise exception 'LOGIN_NECESSARIO';
  end if;
  if char_length(trim(coalesce(p_nome, ''))) not between 2 and 100 then
    raise exception 'NOME_EMPRESA_INVALIDO';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'LINK_EMPRESA_INVALIDO';
  end if;

  insert into public.empresas (nome, slug)
  values (trim(p_nome), v_slug)
  returning id into v_empresa;

  insert into public.empresa_membros (empresa_id, usuario_id, papel)
  values (v_empresa, v_usuario, 'dono');

  insert into public.assinaturas (empresa_id, status, teste_ate)
  values (v_empresa, 'teste', now() + interval '14 days');

  return v_empresa;
end;
$$;

revoke all on function public.criar_empresa(text, text) from public, anon;
grant execute on function public.criar_empresa(text, text) to authenticated;

commit;
