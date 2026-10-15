-- FELJ Controle de Aço — schema isolado.
-- Projeto: jklgvpmgvkooghfhnirq. Este arquivo NÃO altera tabelas preexistentes.
create table if not exists public.aco_lotes (
 id uuid primary key default gen_random_uuid(), codigo_lote text not null,
 fornecedor text not null, nota_fiscal text not null, certificado_path text,
 material text not null default 'H13', diametro_mm numeric(8,2) not null check(diametro_mm>0),
 comprimento_barra_mm integer not null check(comprimento_barra_mm>0),
 quantidade_barras integer not null default 0 check(quantidade_barras>=0),
 localizacao text, observacoes text, ativo boolean not null default true,
 criado_por uuid default auth.uid(), criado_em timestamptz not null default now(),
 atualizado_em timestamptz not null default now()
);
create table if not exists public.aco_listas_corte (
 id uuid primary key default gen_random_uuid(), codigo_lista text not null unique,
 origem text not null default 'manual' check(origem in('manual','importada')),
 arquivo_nome text, arquivo_path text, data_lista date, status text not null default 'aberta' check(status in('aberta','em_corte','concluida','cancelada')),
 observacoes text, criado_por uuid default auth.uid(), criado_em timestamptz not null default now()
);
create table if not exists public.aco_itens_lista_corte (
 id uuid primary key default gen_random_uuid(), lista_id uuid not null references public.aco_listas_corte(id) on delete cascade,
 os text not null, componente text, cliente text, material text not null default 'H13',
 diametro_mm numeric(8,2) not null check(diametro_mm>0), comprimento_mm numeric(10,2) not null check(comprimento_mm>0),
 quantidade_planejada integer not null default 1 check(quantidade_planejada>0),
 quantidade_cortada integer not null default 0 check(quantidade_cortada>=0), observacoes text, projetista text, classe text, codigo_barra text, fonte_linha text, criado_em timestamptz not null default now()
);
create table if not exists public.aco_apontamentos_serra (
 id uuid primary key default gen_random_uuid(), lote_id uuid not null references public.aco_lotes(id),
 item_lista_id uuid references public.aco_itens_lista_corte(id), os text not null, componente text,
 material text not null, diametro_mm numeric(8,2) not null, comprimento_peca_mm numeric(10,2) not null,
 quantidade_pecas integer not null, quantidade_cortes integer not null, perda_corte_mm integer not null,
 consumo_total_mm numeric(12,2) not null, barra_comprimento_mm integer not null, sobra_mm numeric(12,2) not null,
 destino_sobra text not null check(destino_sobra in('reutilizavel','sucata','sem_sobra')),
 observacoes text, operador_id uuid not null default auth.uid(), apontado_em timestamptz not null default now()
);
create table if not exists public.aco_remanescentes (
 id uuid primary key default gen_random_uuid(), lote_origem_id uuid references public.aco_lotes(id),
 apontamento_id uuid references public.aco_apontamentos_serra(id), material text not null,
 diametro_mm numeric(8,2) not null, comprimento_mm integer not null check(comprimento_mm>0),
 quantidade integer not null default 1 check(quantidade>0), localizacao text,
 status text not null default 'disponivel' check(status in('disponivel','reservado','consumido','sucata')),
 criado_em timestamptz not null default now()
);
create table if not exists public.aco_ajustes_inventario (
 id uuid primary key default gen_random_uuid(), lote_id uuid not null references public.aco_lotes(id),
 quantidade_sistema integer not null, quantidade_fisica integer not null check(quantidade_fisica>=0),
 diferenca integer not null, justificativa text not null, aprovado_por uuid default auth.uid(), criado_em timestamptz not null default now()
);
create table if not exists public.aco_movimentacoes (
 id uuid primary key default gen_random_uuid(), lote_id uuid references public.aco_lotes(id),
 tipo text not null check(tipo in('entrada','consumo_serra','ajuste_inventario')),
 quantidade_barras_delta integer not null, comprimento_mm numeric(12,2), referencia text, observacoes text,
 usuario_id uuid default auth.uid(), criado_em timestamptz not null default now()
);
create index if not exists aco_lotes_busca_idx on public.aco_lotes(diametro_mm,material,ativo);
create index if not exists aco_movimentacoes_lote_idx on public.aco_movimentacoes(lote_id,criado_em desc);
create index if not exists aco_itens_lista_lista_idx on public.aco_itens_lista_corte(lista_id);
create index if not exists aco_apontamentos_data_idx on public.aco_apontamentos_serra(apontado_em desc);

create or replace function public.aco_papel_atual() returns text language sql stable security invoker set search_path=''
as $$ select coalesce(auth.jwt()->'app_metadata'->>'role','') $$;
create or replace function public.aco_pode_ver() returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.aco_papel_atual() in('admin','pcp','almoxarifado','serra') $$;
create or replace function public.aco_pode_gerir() returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.aco_papel_atual() in('admin','pcp','almoxarifado') $$;

create or replace function public.aco_registrar_entrada(
 p_codigo_lote text,p_fornecedor text,p_nota_fiscal text,p_certificado_path text,p_material text,
 p_diametro_mm numeric,p_comprimento_barra_mm integer,p_quantidade_barras integer,p_localizacao text,p_observacoes text default null
) returns uuid language plpgsql security invoker set search_path=''
as $$
declare v_id uuid;
begin
 if auth.uid() is null or public.aco_papel_atual() not in('admin','pcp','almoxarifado') then raise exception 'Acesso negado para entrada de estoque'; end if;
 if trim(coalesce(p_codigo_lote,''))='' or trim(coalesce(p_fornecedor,''))='' or trim(coalesce(p_nota_fiscal,''))='' then raise exception 'Lote, fornecedor e NF são obrigatórios'; end if;
 if p_quantidade_barras<1 or p_comprimento_barra_mm<1 or p_diametro_mm<=0 then raise exception 'Dimensões e quantidade devem ser positivas'; end if;
 insert into public.aco_lotes(codigo_lote,fornecedor,nota_fiscal,certificado_path,material,diametro_mm,comprimento_barra_mm,quantidade_barras,localizacao,observacoes)
 values(trim(p_codigo_lote),trim(p_fornecedor),trim(p_nota_fiscal),nullif(trim(coalesce(p_certificado_path,'')),''),trim(p_material),p_diametro_mm,p_comprimento_barra_mm,p_quantidade_barras,nullif(trim(coalesce(p_localizacao,'')),''),p_observacoes) returning id into v_id;
 insert into public.aco_movimentacoes(lote_id,tipo,quantidade_barras_delta,comprimento_mm,referencia,observacoes)
 values(v_id,'entrada',p_quantidade_barras,p_comprimento_barra_mm,p_nota_fiscal,'Entrada inicial do lote '||p_codigo_lote);
 return v_id;
end $$;

create or replace function public.aco_confirmar_ajuste(p_lote_id uuid,p_quantidade_fisica integer,p_justificativa text)
returns uuid language plpgsql security invoker set search_path=''
as $$
declare v_lote public.aco_lotes%rowtype; v_dif integer; v_id uuid;
begin
 if auth.uid() is null or public.aco_papel_atual() not in('admin','pcp','almoxarifado') then raise exception 'Acesso negado para ajuste'; end if;
 if p_quantidade_fisica<0 or length(trim(coalesce(p_justificativa,'')))<5 then raise exception 'Informe contagem e justificativa (mínimo 5 caracteres)'; end if;
 select * into v_lote from public.aco_lotes where id=p_lote_id for update;
 if not found then raise exception 'Lote não encontrado'; end if;
 v_dif:=p_quantidade_fisica-v_lote.quantidade_barras;
 insert into public.aco_ajustes_inventario(lote_id,quantidade_sistema,quantidade_fisica,diferenca,justificativa) values(p_lote_id,v_lote.quantidade_barras,p_quantidade_fisica,v_dif,p_justificativa) returning id into v_id;
 update public.aco_lotes set quantidade_barras=p_quantidade_fisica,atualizado_em=now() where id=p_lote_id;
 insert into public.aco_movimentacoes(lote_id,tipo,quantidade_barras_delta,referencia,observacoes) values(p_lote_id,'ajuste_inventario',v_dif,'Ajuste '||v_id::text,p_justificativa);
 return v_id;
end $$;
revoke all on function public.aco_confirmar_ajuste(uuid,integer,text) from public,anon;
grant execute on function public.aco_confirmar_ajuste(uuid,integer,text) to authenticated;

alter table public.aco_lotes enable row level security;
alter table public.aco_listas_corte enable row level security;
alter table public.aco_itens_lista_corte enable row level security;
alter table public.aco_apontamentos_serra enable row level security;
alter table public.aco_remanescentes enable row level security;
alter table public.aco_ajustes_inventario enable row level security;
alter table public.aco_movimentacoes enable row level security;
drop policy if exists aco_lotes_select on public.aco_lotes;
create policy aco_lotes_select on public.aco_lotes for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_lotes_insert on public.aco_lotes;
create policy aco_lotes_insert on public.aco_lotes for insert to authenticated with check(public.aco_pode_gerir());
drop policy if exists aco_lotes_update on public.aco_lotes;
create policy aco_lotes_update on public.aco_lotes for update to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
drop policy if exists aco_listas_select on public.aco_listas_corte;
create policy aco_listas_select on public.aco_listas_corte for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_listas_manage on public.aco_listas_corte;
create policy aco_listas_manage on public.aco_listas_corte for all to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
drop policy if exists aco_itens_select on public.aco_itens_lista_corte;
create policy aco_itens_select on public.aco_itens_lista_corte for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_itens_manage on public.aco_itens_lista_corte;
create policy aco_itens_manage on public.aco_itens_lista_corte for all to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
drop policy if exists aco_serra_select on public.aco_apontamentos_serra;
create policy aco_serra_select on public.aco_apontamentos_serra for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_serra_insert on public.aco_apontamentos_serra;
create policy aco_serra_insert on public.aco_apontamentos_serra for insert to authenticated with check(auth.uid() is not null and public.aco_papel_atual() in('admin','pcp','serra'));
drop policy if exists aco_rem_select on public.aco_remanescentes;
create policy aco_rem_select on public.aco_remanescentes for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_rem_manage on public.aco_remanescentes;
create policy aco_rem_manage on public.aco_remanescentes for all to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
drop policy if exists aco_ajustes_select on public.aco_ajustes_inventario;
create policy aco_ajustes_select on public.aco_ajustes_inventario for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_ajustes_insert on public.aco_ajustes_inventario;
create policy aco_ajustes_insert on public.aco_ajustes_inventario for insert to authenticated with check(public.aco_pode_gerir());
drop policy if exists aco_mov_select on public.aco_movimentacoes;
create policy aco_mov_select on public.aco_movimentacoes for select to authenticated using(public.aco_pode_ver());
drop policy if exists aco_mov_insert on public.aco_movimentacoes;
create policy aco_mov_insert on public.aco_movimentacoes for insert to authenticated with check(public.aco_pode_gerir());
grant select,insert,update on public.aco_lotes to authenticated;
grant select,insert,update,delete on public.aco_listas_corte,public.aco_itens_lista_corte,public.aco_remanescentes to authenticated;
grant select,insert on public.aco_apontamentos_serra,public.aco_ajustes_inventario,public.aco_movimentacoes to authenticated;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- Reforço de validação de vínculo: impede apontar em OS/medida/material divergentes.
create or replace function private.aco_confirmar_corte(
 p_lote_id uuid,p_item_lista_id uuid,p_os text,p_componente text,p_quantidade_pecas integer,
 p_comprimento_peca_mm numeric,p_quantidade_cortes integer,p_destino_sobra text,p_observacoes text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_lote public.aco_lotes%rowtype; v_item public.aco_itens_lista_corte%rowtype; v_perda integer; v_consumo numeric(12,2); v_sobra numeric(12,2); v_id uuid;
begin
 if auth.uid() is null or public.aco_papel_atual() not in('admin','pcp','serra') then raise exception 'Acesso negado para apontamento de serra'; end if;
 if trim(coalesce(p_os,''))='' or p_quantidade_pecas<1 or p_comprimento_peca_mm<1 or p_quantidade_cortes<1 then raise exception 'OS, quantidades e comprimento são obrigatórios'; end if;
 select * into v_lote from public.aco_lotes where id=p_lote_id and ativo=true for update;
 if not found then raise exception 'Lote não encontrado ou inativo'; end if;
 if v_lote.quantidade_barras<1 then raise exception 'Estoque sem barras disponíveis'; end if;
 if p_item_lista_id is not null then
   select * into v_item from public.aco_itens_lista_corte where id=p_item_lista_id for update;
   if not found then raise exception 'Item da lista de corte não encontrado'; end if;
   if v_item.os<>p_os or v_item.diametro_mm<>v_lote.diametro_mm or v_item.material<>v_lote.material or v_item.comprimento_mm<>p_comprimento_peca_mm then raise exception 'OS, material, diâmetro ou comprimento não correspondem ao item planejado'; end if;
   if v_item.quantidade_cortada+p_quantidade_pecas>v_item.quantidade_planejada then raise exception 'Quantidade excede o saldo planejado deste item'; end if;
 end if;
 v_perda:=case when v_lote.diametro_mm<250 then 3 else 4 end;
 v_consumo:=p_quantidade_pecas*p_comprimento_peca_mm+p_quantidade_cortes*v_perda;
 v_sobra:=v_lote.comprimento_barra_mm-v_consumo;
 if v_sobra<0 then raise exception 'Consumo calculado (%) excede o comprimento da barra (%)',v_consumo,v_lote.comprimento_barra_mm; end if;
 if p_destino_sobra not in('reutilizavel','sucata','sem_sobra') then raise exception 'Destino da sobra inválido'; end if;
 if p_destino_sobra='sem_sobra' and v_sobra>0 then raise exception 'Há sobra calculada; selecione reutilizável ou sucata'; end if;
 if p_destino_sobra='reutilizavel' and v_sobra<100 then raise exception 'Sobra menor que 100 mm: classifique como sucata'; end if;
 update public.aco_lotes set quantidade_barras=quantidade_barras-1,atualizado_em=now() where id=p_lote_id;
 insert into public.aco_apontamentos_serra(lote_id,item_lista_id,os,componente,material,diametro_mm,comprimento_peca_mm,quantidade_pecas,quantidade_cortes,perda_corte_mm,consumo_total_mm,barra_comprimento_mm,sobra_mm,destino_sobra,observacoes)
 values(p_lote_id,p_item_lista_id,p_os,p_componente,v_lote.material,v_lote.diametro_mm,p_comprimento_peca_mm,p_quantidade_pecas,p_quantidade_cortes,v_perda,v_consumo,v_lote.comprimento_barra_mm,v_sobra,p_destino_sobra,p_observacoes) returning id into v_id;
 if p_destino_sobra='reutilizavel' and v_sobra>=100 then insert into public.aco_remanescentes(lote_origem_id,apontamento_id,material,diametro_mm,comprimento_mm,localizacao) values(p_lote_id,v_id,v_lote.material,v_lote.diametro_mm,v_sobra,v_lote.localizacao); end if;
 if p_item_lista_id is not null then update public.aco_itens_lista_corte set quantidade_cortada=quantidade_cortada+p_quantidade_pecas where id=p_item_lista_id; end if;
 insert into public.aco_movimentacoes(lote_id,tipo,quantidade_barras_delta,comprimento_mm,referencia,observacoes) values(p_lote_id,'consumo_serra',-1,v_consumo,p_os,'Apontamento serra '||v_id::text);
 return v_id;
end $$;
revoke all on function private.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) from public,anon;
grant execute on function private.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) to authenticated;
-- O schema privado não é exposto pela API; só usuários autenticados podem executar a rotina via wrapper.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
revoke all on function private.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) from public, anon;
grant execute on function private.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) to authenticated;
create or replace function public.aco_confirmar_corte(
 p_lote_id uuid,p_item_lista_id uuid,p_os text,p_componente text,p_quantidade_pecas integer,
 p_comprimento_peca_mm numeric,p_quantidade_cortes integer,p_destino_sobra text,p_observacoes text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.aco_confirmar_corte(p_lote_id,p_item_lista_id,p_os,p_componente,p_quantidade_pecas,p_comprimento_peca_mm,p_quantidade_cortes,p_destino_sobra,p_observacoes) $$;
revoke all on function public.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) from public, anon;
grant execute on function public.aco_confirmar_corte(uuid,uuid,text,text,integer,numeric,integer,text,text) to authenticated;
revoke all on function public.aco_registrar_entrada(text,text,text,text,text,numeric,integer,integer,text,text) from public, anon;
grant execute on function public.aco_registrar_entrada(text,text,text,text,text,numeric,integer,integer,text,text) to authenticated;

-- Bucket privado para certificados; o acesso é concedido por políticas RLS de Storage.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('aco-certificados','aco-certificados',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf','image/jpeg','image/png'];
drop policy if exists aco_certificados_read on storage.objects;
create policy aco_certificados_read on storage.objects for select to authenticated
using (bucket_id='aco-certificados' and (select public.aco_pode_ver()));
drop policy if exists aco_certificados_upload on storage.objects;
create policy aco_certificados_upload on storage.objects for insert to authenticated
with check (bucket_id='aco-certificados' and (select public.aco_pode_gerir()) and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists aco_certificados_update on storage.objects;
create policy aco_certificados_update on storage.objects for update to authenticated
using (bucket_id='aco-certificados' and (select public.aco_pode_gerir()) and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='aco-certificados' and (select public.aco_pode_gerir()) and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists aco_certificados_delete on storage.objects;
create policy aco_certificados_delete on storage.objects for delete to authenticated
using (bucket_id='aco-certificados' and (select public.aco_pode_gerir()) and (storage.foldername(name))[1]=(select auth.uid())::text);


-- Índices das chaves estrangeiras e ajustes de políticas para evitar políticas SELECT duplicadas.
create index if not exists aco_ajustes_lote_idx on public.aco_ajustes_inventario(lote_id);
create index if not exists aco_apontamentos_lote_idx on public.aco_apontamentos_serra(lote_id);
create index if not exists aco_apontamentos_item_idx on public.aco_apontamentos_serra(item_lista_id);
create index if not exists aco_remanescentes_lote_idx on public.aco_remanescentes(lote_origem_id);
create index if not exists aco_remanescentes_apontamento_idx on public.aco_remanescentes(apontamento_id);
drop policy if exists aco_listas_manage on public.aco_listas_corte;
drop policy if exists aco_listas_insert on public.aco_listas_corte;
drop policy if exists aco_listas_update on public.aco_listas_corte;
drop policy if exists aco_listas_delete on public.aco_listas_corte;
create policy aco_listas_insert on public.aco_listas_corte for insert to authenticated with check(public.aco_pode_gerir());
create policy aco_listas_update on public.aco_listas_corte for update to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
create policy aco_listas_delete on public.aco_listas_corte for delete to authenticated using(public.aco_pode_gerir());
drop policy if exists aco_itens_manage on public.aco_itens_lista_corte;
drop policy if exists aco_itens_insert on public.aco_itens_lista_corte;
drop policy if exists aco_itens_update on public.aco_itens_lista_corte;
drop policy if exists aco_itens_delete on public.aco_itens_lista_corte;
create policy aco_itens_insert on public.aco_itens_lista_corte for insert to authenticated with check(public.aco_pode_gerir());
create policy aco_itens_update on public.aco_itens_lista_corte for update to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
create policy aco_itens_delete on public.aco_itens_lista_corte for delete to authenticated using(public.aco_pode_gerir());
drop policy if exists aco_rem_manage on public.aco_remanescentes;
drop policy if exists aco_rem_insert on public.aco_remanescentes;
drop policy if exists aco_rem_update on public.aco_remanescentes;
drop policy if exists aco_rem_delete on public.aco_remanescentes;
create policy aco_rem_insert on public.aco_remanescentes for insert to authenticated with check(public.aco_pode_gerir());
create policy aco_rem_update on public.aco_remanescentes for update to authenticated using(public.aco_pode_gerir()) with check(public.aco_pode_gerir());
create policy aco_rem_delete on public.aco_remanescentes for delete to authenticated using(public.aco_pode_gerir());
drop policy if exists aco_serra_insert on public.aco_apontamentos_serra;
create policy aco_serra_insert on public.aco_apontamentos_serra for insert to authenticated with check((select auth.uid()) is not null and (select public.aco_papel_atual()) in('admin','pcp','serra'));

-- PDF da lista de corte em bucket privado; importação transacional da lista e de seus itens.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('aco-listas-pdf','aco-listas-pdf',false,20971520,array['application/pdf'])
on conflict (id) do update set public=false,file_size_limit=20971520,allowed_mime_types=array['application/pdf'];
drop policy if exists aco_listas_pdf_read on storage.objects;
create policy aco_listas_pdf_read on storage.objects for select to authenticated
using (bucket_id='aco-listas-pdf' and (select public.aco_pode_ver()));
drop policy if exists aco_listas_pdf_upload on storage.objects;
create policy aco_listas_pdf_upload on storage.objects for insert to authenticated
with check (bucket_id='aco-listas-pdf' and (select public.aco_papel_atual()) in ('admin','pcp') and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists aco_listas_pdf_update on storage.objects;
create policy aco_listas_pdf_update on storage.objects for update to authenticated
using (bucket_id='aco-listas-pdf' and (select public.aco_papel_atual()) in ('admin','pcp') and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='aco-listas-pdf' and (select public.aco_papel_atual()) in ('admin','pcp') and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists aco_listas_pdf_delete on storage.objects;
create policy aco_listas_pdf_delete on storage.objects for delete to authenticated
using (bucket_id='aco-listas-pdf' and (select public.aco_papel_atual()) in ('admin','pcp') and (storage.foldername(name))[1]=(select auth.uid())::text);
create or replace function public.aco_importar_lista_corte(
 p_codigo_lista text,p_arquivo_nome text,p_arquivo_path text,p_data_lista date,p_itens jsonb,p_observacoes text default null
) returns uuid language plpgsql security invoker set search_path=''
as $$
declare v_lista_id uuid; v_item jsonb;
begin
 if auth.uid() is null or public.aco_papel_atual() not in ('admin','pcp') then raise exception 'Somente administrador ou PCP pode importar listas'; end if;
 if trim(coalesce(p_codigo_lista,''))='' or jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)=0 then raise exception 'Código e itens da lista são obrigatórios'; end if;
 if p_arquivo_path is not null and (storage.foldername(p_arquivo_path))[1]<>auth.uid()::text then raise exception 'Caminho do PDF inválido'; end if;
 insert into public.aco_listas_corte(codigo_lista,origem,arquivo_nome,arquivo_path,data_lista,observacoes)
 values(trim(p_codigo_lista),'importada',p_arquivo_nome,p_arquivo_path,p_data_lista,p_observacoes) returning id into v_lista_id;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   if coalesce(trim(v_item->>'os'),'')='' or coalesce(trim(v_item->>'componente'),'')='' or nullif(v_item->>'diametro_mm','') is null or nullif(v_item->>'comprimento_mm','') is null then raise exception 'Há item sem OS, componente, diâmetro ou comprimento'; end if;
   insert into public.aco_itens_lista_corte(lista_id,os,componente,cliente,material,diametro_mm,comprimento_mm,quantidade_planejada,projetista,classe,codigo_barra,fonte_linha)
   values(v_lista_id,trim(v_item->>'os'),trim(v_item->>'componente'),nullif(trim(coalesce(v_item->>'cliente','')),''),coalesce(nullif(trim(v_item->>'material'),''),'H13'),
     (v_item->>'diametro_mm')::numeric,(v_item->>'comprimento_mm')::numeric,1,
     nullif(trim(coalesce(v_item->>'projetista','')),''),nullif(trim(coalesce(v_item->>'classe','')),''),nullif(trim(coalesce(v_item->>'codigo_barra','')),''),nullif(trim(coalesce(v_item->>'fonte_linha','')),''));
 end loop;
 return v_lista_id;
end $$;
revoke all on function public.aco_importar_lista_corte(text,text,text,date,jsonb,text) from public,anon;
grant execute on function public.aco_importar_lista_corte(text,text,text,date,jsonb,text) to authenticated;
