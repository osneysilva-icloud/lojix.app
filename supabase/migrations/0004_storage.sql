-- =============================================================================
-- LOJIX — 0004_storage.sql
-- Buckets e políticas de Storage. Estrutura de caminhos: {store_id}/{tipo}/{ficheiro}
--  - store-public : imagens (logótipos, banners, produtos, categorias, páginas). Leitura pública por URL.
--  - store-private: ficheiros digitais. Sem acesso público; descarga só por URL assinada
--                   emitida pelo servidor após validar a encomenda paga.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('store-public', 'store-public', true, 5242880, array['image/webp', 'image/jpeg', 'image/png']),
  ('store-private', 'store-private', false, 52428800,
    array['application/pdf', 'application/zip', 'application/epub+zip', 'audio/mpeg', 'video/mp4',
          'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Extrai o store_id do primeiro segmento do caminho; devolve null se inválido
create or replace function public.storage_store_id(p_name text)
returns uuid language plpgsql immutable as $$
declare v text := split_part(p_name, '/', 1);
begin
  if v ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return v::uuid;
  end if;
  return null;
end;
$$;
grant execute on function public.storage_store_id(text) to anon, authenticated;

-- Sem política de SELECT para anon: o acesso público faz-se por URL do bucket público.
create policy "lojix_storage_select_members" on storage.objects for select to authenticated
  using (
    bucket_id in ('store-public', 'store-private')
    and public.storage_store_id(name) is not null
    and (public.is_store_member(public.storage_store_id(name)) or public.is_superadmin())
  );

create policy "lojix_storage_insert_managers" on storage.objects for insert to authenticated
  with check (
    bucket_id in ('store-public', 'store-private')
    and public.storage_store_id(name) is not null
    and public.can_manage_store(public.storage_store_id(name))
  );

create policy "lojix_storage_update_managers" on storage.objects for update to authenticated
  using (
    bucket_id in ('store-public', 'store-private')
    and public.storage_store_id(name) is not null
    and public.can_manage_store(public.storage_store_id(name))
  )
  with check (
    bucket_id in ('store-public', 'store-private')
    and public.storage_store_id(name) is not null
    and public.can_manage_store(public.storage_store_id(name))
  );

create policy "lojix_storage_delete_managers" on storage.objects for delete to authenticated
  using (
    bucket_id in ('store-public', 'store-private')
    and public.storage_store_id(name) is not null
    and public.can_manage_store(public.storage_store_id(name))
  );
