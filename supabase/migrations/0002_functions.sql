-- =============================================================================
-- LOJIX — 0002_functions.sql
-- Funções auxiliares, triggers de integridade/segurança, limites de plano e RPCs.
-- Erros de negócio usam errcode P0001 com mensagem = código (ex.: plan_limit_products).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Auxiliares de identidade/permissões
-- ---------------------------------------------------------------------------
create or replace function public.is_privileged_db_role()
returns boolean language sql stable as $$
  select current_user in ('postgres', 'service_role', 'supabase_admin', 'supabase_auth_admin')
$$;

create or replace function public.is_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.platform_role = 'superadmin' and p.status = 'active'
  )
$$;

create or replace function public.store_role(p_store uuid)
returns text language sql stable security definer set search_path = public as $$
  select sm.role
  from public.store_members sm
  join public.profiles p on p.id = sm.user_id
  where sm.store_id = p_store and sm.user_id = auth.uid() and p.status = 'active'
$$;

create or replace function public.is_store_member(p_store uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.store_role(p_store) is not null
$$;

create or replace function public.can_manage_store(p_store uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.store_role(p_store) in ('owner', 'admin'), false)
$$;

create or replace function public.store_is_public(p_store uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.stores s
    join public.profiles p on p.id = s.owner_id
    where s.id = p_store and s.status = 'published' and p.status = 'active'
  )
$$;

create or replace function public.product_is_public(p_product uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.products pr
    where pr.id = p_product and pr.status = 'published' and public.store_is_public(pr.store_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- Planos
-- ---------------------------------------------------------------------------
create or replace function public.owner_plan(p_owner uuid)
returns public.plans language plpgsql stable security definer set search_path = public as $$
declare v public.plans;
begin
  select pl.* into v
  from public.plans pl
  join public.subscriptions s on s.plan_id = pl.id
  where s.owner_id = p_owner
    and s.status in ('trialing', 'active', 'past_due')
    and (s.expires_at is null or s.expires_at > now())
  limit 1;
  if v.id is null then
    select * into v from public.plans where is_default limit 1;
  end if;
  return v;
end;
$$;

create or replace function public.plan_feature(p_owner uuid, p_key text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v public.plans;
begin
  v := public.owner_plan(p_owner);
  if v.id is null then return false; end if;
  return coalesce((v.features ->> p_key)::boolean, false);
end;
$$;

create or replace function public.tg_enforce_store_limits()
returns trigger language plpgsql security definer set search_path = public as $$
declare v public.plans; v_count integer;
begin
  v := public.owner_plan(new.owner_id);
  if v.id is null then
    raise exception 'plan_missing' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    if v.max_stores is not null then
      select count(*) into v_count from public.stores
       where owner_id = new.owner_id and status <> 'archived';
      if v_count >= v.max_stores then
        raise exception 'plan_limit_stores' using errcode = 'P0001';
      end if;
    end if;
  end if;
  if tg_op = 'INSERT' or new.template_key is distinct from old.template_key then
    if not (new.template_key = any (v.template_keys)) then
      raise exception 'plan_template_not_allowed' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.tg_enforce_product_limits()
returns trigger language plpgsql security definer set search_path = public as $$
declare v public.plans; v_owner uuid; v_count integer;
begin
  select owner_id into v_owner from public.stores where id = new.store_id;
  v := public.owner_plan(v_owner);
  if v.id is null then raise exception 'plan_missing' using errcode = 'P0001'; end if;
  if v.max_products is not null then
    select count(*) into v_count from public.products
     where store_id = new.store_id and status <> 'archived';
    if v_count >= v.max_products then
      raise exception 'plan_limit_products' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.tg_enforce_storage_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v public.plans; v_owner uuid; v_used bigint;
begin
  select owner_id into v_owner from public.stores where id = new.store_id;
  v := public.owner_plan(v_owner);
  if v.id is null then raise exception 'plan_missing' using errcode = 'P0001'; end if;
  if v.storage_limit_mb is not null then
    select coalesce(sum(size_bytes), 0) into v_used from public.media_files where store_id = new.store_id;
    if v_used + new.size_bytes > v.storage_limit_mb::bigint * 1024 * 1024 then
      raise exception 'plan_limit_storage' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.storage_usage_bytes(p_store uuid)
returns bigint language sql stable security invoker set search_path = public as $$
  select coalesce(sum(size_bytes), 0)::bigint from public.media_files where store_id = p_store
$$;

-- ---------------------------------------------------------------------------
-- Perfis / registo
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_plan uuid; v_sub uuid;
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, coalesce(new.email, ''), left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120));

  select id into v_plan from public.plans where is_default limit 1;
  if v_plan is not null then
    insert into public.subscriptions (owner_id, plan_id, status)
    values (new.id, v_plan, 'active');
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_email_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is distinct from old.email and new.email is not null then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();

-- Impede alterações de papel/estado/e-mail por utilizadores comuns (defesa em profundidade;
-- as grants por coluna já o impedem).
create or replace function public.tg_guard_profile_update()
returns trigger language plpgsql as $$
begin
  if public.is_privileged_db_role() then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.platform_role is distinct from old.platform_role
     or new.status is distinct from old.status
     or new.suspended_reason is distinct from old.suspended_reason
     or new.email is distinct from old.email then
    raise exception 'forbidden_profile_field' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.tg_guard_profile_update();

create or replace function public.touch_last_seen()
returns void language sql security definer set search_path = public as $$
  update public.profiles set last_seen_at = now()
  where id = auth.uid() and (last_seen_at is null or last_seen_at < now() - interval '10 minutes')
$$;

-- ---------------------------------------------------------------------------
-- Slugs e lojas
-- ---------------------------------------------------------------------------
create or replace function public.slug_availability(p_slug text, p_store uuid default null)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$' or p_slug ~ '--' then
    return 'invalid';
  end if;
  if exists (select 1 from public.reserved_slugs where slug = p_slug) then
    return 'reserved';
  end if;
  if exists (select 1 from public.stores where slug = p_slug and (p_store is null or id <> p_store)) then
    return 'taken';
  end if;
  if exists (select 1 from public.store_slug_history h
             where h.old_slug = p_slug and (p_store is null or h.store_id <> p_store)) then
    return 'taken';
  end if;
  return 'available';
end;
$$;

create or replace function public.tg_validate_store_slug()
returns trigger language plpgsql as $$
declare v text;
begin
  if tg_op = 'INSERT' or new.slug is distinct from old.slug then
    v := public.slug_availability(new.slug, new.id);
    if v <> 'available' then
      raise exception 'slug_%', v using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
create trigger stores_validate_slug before insert or update of slug on public.stores
  for each row execute function public.tg_validate_store_slug();

create trigger stores_enforce_limits before insert or update of template_key on public.stores
  for each row execute function public.tg_enforce_store_limits();

-- Invoker (não security definer): current_user reflete o papel real do chamador.
-- Funções SECURITY DEFINER internas (change_store_slug, publish_store_settings) executam como
-- dono e são consideradas fiáveis.
create or replace function public.tg_guard_store_update()
returns trigger language plpgsql set search_path = public as $$
declare v_super boolean;
begin
  if new.status = 'published' and old.status is distinct from 'published' then
    new.published_at := now();
  end if;

  if public.is_privileged_db_role() then
    return new;
  end if;

  v_super := public.is_superadmin();

  if new.owner_id is distinct from old.owner_id then
    raise exception 'forbidden_store_field' using errcode = '42501';
  end if;

  if not v_super then
    if new.slug is distinct from old.slug
       or new.suspended_reason is distinct from old.suspended_reason
       or new.published_theme is distinct from old.published_theme
       or new.theme_published_at is distinct from old.theme_published_at
       or new.slug_changed_at is distinct from old.slug_changed_at
       or new.next_order_number is distinct from old.next_order_number then
      raise exception 'forbidden_store_field' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
      if old.status = 'suspended' or new.status = 'suspended' then
        raise exception 'forbidden_store_status' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger stores_guard_update before update on public.stores
  for each row execute function public.tg_guard_store_update();

create or replace function public.tg_store_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.store_members (store_id, user_id, role) values (new.id, new.owner_id, 'owner');
  insert into public.store_settings (store_id) values (new.id);
  return new;
end;
$$;
create trigger stores_after_insert after insert on public.stores
  for each row execute function public.tg_store_after_insert();

create or replace function public.tg_record_slug_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.slug is distinct from old.slug then
    insert into public.store_slug_history (store_id, old_slug) values (old.id, old.slug);
    new.slug_changed_at := now();
  end if;
  return new;
end;
$$;
-- BEFORE para poder ajustar slug_changed_at (executa depois da validação por ordem alfabética)
create trigger stores_zz_record_slug_change before update of slug on public.stores
  for each row execute function public.tg_record_slug_change();

create or replace function public.change_store_slug(p_store uuid, p_slug text)
returns text language plpgsql security definer set search_path = public as $$
declare v_slug text := lower(btrim(p_slug)); v_store public.stores;
begin
  select * into v_store from public.stores where id = p_store for update;
  if not found then raise exception 'store_not_found' using errcode = 'P0001'; end if;
  if not (coalesce(public.store_role(p_store) = 'owner', false) or public.is_superadmin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_store.slug = v_slug then return v_slug; end if;
  if v_store.slug_changed_at is not null and v_store.slug_changed_at > now() - interval '30 days'
     and not public.is_superadmin() then
    raise exception 'slug_change_cooldown' using errcode = 'P0001';
  end if;
  update public.stores set slug = v_slug where id = p_store;
  return v_slug;
end;
$$;

create or replace function public.resolve_store_state(p_slug text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when s.id is null then 'unknown'
    when p.status <> 'active' then 'suspended'
    else s.status
  end
  from (select 1) x
  left join public.stores s on s.slug = lower(p_slug)
  left join public.profiles p on p.id = s.owner_id
$$;

-- ---------------------------------------------------------------------------
-- Integridade de catálogo
-- ---------------------------------------------------------------------------
create or replace function public.tg_product_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_currency text; v_kind text;
begin
  select currency into v_currency from public.stores where id = new.store_id;
  new.currency := v_currency;
  if new.track_stock and new.stock_quantity is null then new.stock_quantity := 0; end if;
  if jsonb_typeof(new.option_definitions) is distinct from 'array' then
    raise exception 'invalid_option_definitions' using errcode = 'P0001';
  end if;
  if jsonb_typeof(new.customization_options) is distinct from 'array' then
    raise exception 'invalid_customization_options' using errcode = 'P0001';
  end if;
  if new.digital_media_id is not null then
    select kind into v_kind from public.media_files where id = new.digital_media_id;
    if v_kind is distinct from 'digital' then
      raise exception 'invalid_digital_media' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
create trigger products_before_write before insert or update on public.products
  for each row execute function public.tg_product_before_write();
create trigger products_enforce_limits before insert on public.products
  for each row execute function public.tg_enforce_product_limits();

create or replace function public.tg_variant_before_write()
returns trigger language plpgsql as $$
begin
  if jsonb_typeof(new.option_values) is distinct from 'object' or new.option_values = '{}'::jsonb then
    raise exception 'invalid_variant_options' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger product_variants_before_write before insert or update on public.product_variants
  for each row execute function public.tg_variant_before_write();

create or replace function public.tg_image_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_count integer; v_kind text;
begin
  select kind into v_kind from public.media_files where id = new.media_id;
  if v_kind is distinct from 'product' then
    raise exception 'invalid_media_kind' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    select count(*) into v_count from public.product_images where product_id = new.product_id;
    if v_count >= 20 then raise exception 'too_many_images' using errcode = 'P0001'; end if;
  end if;
  return new;
end;
$$;
create trigger product_images_before_write before insert or update on public.product_images
  for each row execute function public.tg_image_before_write();

create trigger media_files_enforce_storage before insert on public.media_files
  for each row execute function public.tg_enforce_storage_limit();

create or replace function public.tg_settings_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_kind text; r record;
begin
  select owner_id into v_owner from public.stores where id = new.store_id;
  if new.meta_pixel_id is not null and (tg_op = 'INSERT' or new.meta_pixel_id is distinct from old.meta_pixel_id) then
    if not public.plan_feature(v_owner, 'meta_pixel') then
      raise exception 'plan_feature_meta_pixel' using errcode = 'P0001';
    end if;
  end if;
  for r in
    select * from (values
      (new.logo_media_id, 'logo'), (new.favicon_media_id, 'favicon'),
      (new.banner_media_id, 'banner'), (new.cover_media_id, 'cover')
    ) as t(media_id, expected)
  loop
    if r.media_id is not null then
      select kind into v_kind from public.media_files where id = r.media_id;
      if v_kind is distinct from r.expected then
        raise exception 'invalid_media_kind' using errcode = 'P0001';
      end if;
    end if;
  end loop;
  return new;
end;
$$;
create trigger store_settings_before_write before insert or update on public.store_settings
  for each row execute function public.tg_settings_before_write();

-- Bloqueia remoção de categorias com produtos (validação de dependências)
create or replace function public.tg_category_before_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.product_categories where category_id = old.id) then
    raise exception 'category_has_products' using errcode = 'P0001';
  end if;
  return old;
end;
$$;
create trigger categories_before_delete before delete on public.categories
  for each row execute function public.tg_category_before_delete();

-- ---------------------------------------------------------------------------
-- Publicação da personalização (snapshot público)
-- ---------------------------------------------------------------------------
create or replace function public.build_store_theme(p_store uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.store_settings; v_owner uuid; v_pixel text;
begin
  select * into s from public.store_settings where store_id = p_store;
  select owner_id into v_owner from public.stores where id = p_store;
  v_pixel := case when public.plan_feature(v_owner, 'meta_pixel') then s.meta_pixel_id else null end;
  return jsonb_build_object(
    'description', s.description,
    'primary_color', s.primary_color,
    'secondary_color', s.secondary_color,
    'button_color', s.button_color,
    'font_key', s.font_key,
    'logo_path', (select path from public.media_files where id = s.logo_media_id),
    'favicon_path', (select path from public.media_files where id = s.favicon_media_id),
    'banner_path', (select path from public.media_files where id = s.banner_media_id),
    'cover_path', (select path from public.media_files where id = s.cover_media_id),
    'banner_title', s.banner_title,
    'banner_subtitle', s.banner_subtitle,
    'contact_email', s.contact_email,
    'phone', s.phone,
    'whatsapp_number', s.whatsapp_number,
    'address', s.address,
    'location_url', s.location_url,
    'business_hours', s.business_hours,
    'social_links', s.social_links,
    'delivery_info', s.delivery_info,
    'returns_policy', s.returns_policy,
    'payment_methods', to_jsonb(s.payment_methods),
    'delivery_enabled', s.delivery_enabled,
    'delivery_fee_cents', s.delivery_fee_cents,
    'footer_text', s.footer_text,
    'home_sections', s.home_sections,
    'seo_title', s.seo_title,
    'seo_description', s.seo_description,
    'meta_pixel_id', v_pixel
  );
end;
$$;

create or replace function public.publish_store_settings(p_store uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.can_manage_store(p_store) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v := public.build_store_theme(p_store);
  update public.stores set published_theme = v, theme_published_at = now() where id = p_store;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Encomendas
-- ---------------------------------------------------------------------------
create or replace function public.tg_order_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.order_status_history (store_id, order_id, from_status, to_status, changed_by)
  values (new.store_id, new.id, null, new.status, auth.uid());
  return new;
end;
$$;
create trigger orders_after_insert after insert on public.orders
  for each row execute function public.tg_order_after_insert();

create or replace function public.tg_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_reserved text[] := array['confirmed', 'preparing', 'shipped', 'completed'];
  v_was boolean; v_is boolean; it record;
begin
  if new.status is distinct from old.status then
    insert into public.order_status_history (store_id, order_id, from_status, to_status, changed_by)
    values (new.store_id, new.id, old.status, new.status, auth.uid());

    v_was := old.status = any (v_reserved);
    v_is := new.status = any (v_reserved);
    if v_was <> v_is then
      for it in
        select oi.product_id, oi.variant_id, oi.quantity
        from public.order_items oi where oi.order_id = new.id and oi.product_id is not null
      loop
        if it.variant_id is not null then
          update public.product_variants pv
             set stock_quantity = greatest(0, coalesce(pv.stock_quantity, 0) + case when v_is then -it.quantity else it.quantity end)
           where pv.id = it.variant_id
             and exists (select 1 from public.products p where p.id = pv.product_id and p.track_stock);
        else
          update public.products p
             set stock_quantity = greatest(0, coalesce(p.stock_quantity, 0) + case when v_is then -it.quantity else it.quantity end)
           where p.id = it.product_id and p.track_stock;
        end if;
      end loop;
    end if;
  end if;
  return new;
end;
$$;
create trigger orders_status_change after update of status on public.orders
  for each row execute function public.tg_order_status_change();

create or replace function public.create_whatsapp_order(p_store_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_store public.stores;
  v_theme jsonb;
  v_owner_active boolean;
  v_cust jsonb := p_payload -> 'customer';
  v_items jsonb := p_payload -> 'items';
  v_name text; v_phone text; v_province text; v_city text; v_neigh text; v_addr text; v_notes text;
  v_delivery text; v_payment text; v_methods jsonb;
  v_item jsonb; v_prod public.products; v_var public.product_variants;
  v_qty integer; v_unit bigint; v_subtotal bigint := 0; v_label text; v_stock integer;
  v_customer uuid; v_order uuid; v_seq integer; v_number text; v_fee bigint; v_token text;
  v_custom jsonb; v_pid text; v_vid text; v_recent integer;
begin
  if jsonb_typeof(v_cust) is distinct from 'object' then
    raise exception 'invalid_customer' using errcode = 'P0001';
  end if;

  select * into v_store from public.stores where id = p_store_id for update;
  if not found or v_store.status <> 'published' then
    raise exception 'store_unavailable' using errcode = 'P0001';
  end if;
  select (status = 'active') into v_owner_active from public.profiles where id = v_store.owner_id;
  if not coalesce(v_owner_active, false) then
    raise exception 'store_unavailable' using errcode = 'P0001';
  end if;

  v_theme := coalesce(v_store.published_theme, public.build_store_theme(p_store_id));
  if coalesce(v_theme ->> 'whatsapp_number', '') = '' then
    raise exception 'whatsapp_not_configured' using errcode = 'P0001';
  end if;

  v_name := btrim(coalesce(v_cust ->> 'name', ''));
  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'invalid_customer_name' using errcode = 'P0001';
  end if;
  v_phone := regexp_replace(coalesce(v_cust ->> 'phone', ''), '[^0-9]', '', 'g');
  if v_phone !~ '^[0-9]{7,15}$' then
    raise exception 'invalid_customer_phone' using errcode = 'P0001';
  end if;
  v_province := nullif(left(btrim(coalesce(v_cust ->> 'province', '')), 80), '');
  v_city := nullif(left(btrim(coalesce(v_cust ->> 'city', '')), 80), '');
  v_neigh := nullif(left(btrim(coalesce(v_cust ->> 'neighborhood', '')), 80), '');
  v_addr := nullif(left(btrim(coalesce(v_cust ->> 'address', '')), 300), '');
  v_notes := left(btrim(coalesce(p_payload ->> 'notes', '')), 2000);

  v_delivery := coalesce(p_payload ->> 'delivery_method', 'to_confirm');
  if v_delivery not in ('delivery', 'pickup', 'to_confirm') then
    raise exception 'invalid_delivery_method' using errcode = 'P0001';
  end if;

  v_payment := nullif(btrim(coalesce(p_payload ->> 'payment_method', '')), '');
  v_methods := coalesce(v_theme -> 'payment_methods', '[]'::jsonb);
  if v_payment is not null and jsonb_array_length(v_methods) > 0 and not (v_methods ? v_payment) then
    raise exception 'payment_method_not_accepted' using errcode = 'P0001';
  end if;

  if jsonb_typeof(v_items) is distinct from 'array'
     or jsonb_array_length(v_items) < 1 or jsonb_array_length(v_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  select count(*) into v_recent from public.orders
   where store_id = p_store_id and customer_phone = v_phone and created_at > now() - interval '1 hour';
  if v_recent >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  v_seq := v_store.next_order_number;
  v_number := 'LX-' || v_seq::text;
  update public.stores set next_order_number = v_seq + 1 where id = p_store_id;

  insert into public.customers (store_id, name, phone, province, city)
  values (p_store_id, v_name, v_phone, v_province, v_city)
  on conflict (store_id, phone) do update
    set name = excluded.name,
        province = coalesce(excluded.province, public.customers.province),
        city = coalesce(excluded.city, public.customers.city)
  returning id into v_customer;

  v_fee := case
    when v_delivery = 'delivery' and coalesce((v_theme ->> 'delivery_enabled')::boolean, true)
      then nullif(v_theme ->> 'delivery_fee_cents', '')::bigint
    else null end;

  insert into public.orders (
    store_id, order_number, customer_id, customer_name, customer_phone, province, city, neighborhood,
    address, notes, delivery_method, payment_method, currency, subtotal_cents, total_cents, source
  ) values (
    p_store_id, v_number, v_customer, v_name, v_phone, v_province, v_city, v_neigh,
    v_addr, v_notes, v_delivery, v_payment, v_store.currency, 0, 0, left(p_payload ->> 'source', 60)
  ) returning id, access_token into v_order, v_token;

  for v_item in select * from jsonb_array_elements(v_items) loop
    v_pid := v_item ->> 'product_id';
    v_vid := nullif(v_item ->> 'variant_id', '');
    if v_pid is null or v_pid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (v_vid is not null and v_vid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
      raise exception 'invalid_items' using errcode = 'P0001';
    end if;
    begin
      v_qty := (v_item ->> 'quantity')::integer;
    exception when others then
      raise exception 'invalid_quantity' using errcode = 'P0001';
    end;
    if v_qty is null or v_qty < 1 or v_qty > 99 then
      raise exception 'invalid_quantity' using errcode = 'P0001';
    end if;

    select * into v_prod from public.products
     where id = v_pid::uuid and store_id = p_store_id and status = 'published';
    if not found then raise exception 'product_unavailable' using errcode = 'P0001'; end if;

    v_var := null; v_label := null;
    if exists (select 1 from public.product_variants where product_id = v_prod.id and is_active) then
      if v_vid is null then raise exception 'variant_required' using errcode = 'P0001'; end if;
      select * into v_var from public.product_variants
       where id = v_vid::uuid and product_id = v_prod.id and is_active;
      if not found then raise exception 'variant_unavailable' using errcode = 'P0001'; end if;
      select string_agg(k || ': ' || val, ' / ' order by k) into v_label
        from jsonb_each_text(v_var.option_values) as e(k, val);
    elsif v_vid is not null then
      raise exception 'variant_unavailable' using errcode = 'P0001';
    end if;

    v_unit := coalesce(v_var.price_cents, v_prod.sale_price_cents, v_prod.price_cents);

    if v_prod.track_stock then
      v_stock := case when v_var.id is not null then v_var.stock_quantity else v_prod.stock_quantity end;
      if coalesce(v_stock, 0) < v_qty then
        raise exception 'insufficient_stock' using errcode = 'P0001';
      end if;
    end if;

    v_custom := v_item -> 'customization';
    if v_custom is not null and (jsonb_typeof(v_custom) <> 'object' or length(v_custom::text) > 2000) then
      v_custom := null;
    end if;

    insert into public.order_items (
      store_id, order_id, product_id, variant_id, product_name, product_type, variant_label, sku,
      unit_price_cents, quantity, line_total_cents, customization
    ) values (
      p_store_id, v_order, v_prod.id, v_var.id, v_prod.name, v_prod.product_type, v_label,
      coalesce(v_var.sku, v_prod.sku), v_unit, v_qty, v_unit * v_qty, v_custom
    );
    v_subtotal := v_subtotal + v_unit * v_qty;
  end loop;

  update public.orders
     set subtotal_cents = v_subtotal, delivery_fee_cents = v_fee, total_cents = v_subtotal + coalesce(v_fee, 0)
   where id = v_order;

  insert into public.analytics_events (store_id, event_type, path)
  values (p_store_id, 'order_created', null);

  return jsonb_build_object(
    'order_id', v_order,
    'order_number', v_number,
    'access_token', v_token,
    'currency', v_store.currency,
    'subtotal_cents', v_subtotal,
    'delivery_fee_cents', v_fee,
    'total_cents', v_subtotal + coalesce(v_fee, 0),
    'whatsapp_number', v_theme ->> 'whatsapp_number'
  );
end;
$$;

create or replace function public.record_whatsapp_click(p_token text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_store uuid;
begin
  update public.orders set whatsapp_opened_at = coalesce(whatsapp_opened_at, now())
   where access_token = p_token returning store_id into v_store;
  if v_store is null then return false; end if;
  insert into public.analytics_events (store_id, event_type) values (v_store, 'order_click');
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Assinaturas: histórico e eventos de pagamento (apenas servidor/service_role)
-- ---------------------------------------------------------------------------
create or replace function public.tg_subscription_history()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.subscription_events (subscription_id, owner_id, event_type, to_status, to_plan_id, actor_id)
    values (new.id, new.owner_id, 'created', new.status, new.plan_id, auth.uid());
  elsif new.status is distinct from old.status or new.plan_id is distinct from old.plan_id then
    insert into public.subscription_events
      (subscription_id, owner_id, event_type, from_status, to_status, from_plan_id, to_plan_id, actor_id)
    values (new.id, new.owner_id,
      case when new.plan_id is distinct from old.plan_id then 'plan_changed' else 'status_changed' end,
      old.status, new.status, old.plan_id, new.plan_id, auth.uid());
  end if;
  return new;
end;
$$;
create trigger subscriptions_history after insert or update on public.subscriptions
  for each row execute function public.tg_subscription_history();

-- Só deve ser chamada por um webhook cuja assinatura já foi verificada no servidor.
create or replace function public.apply_payment_event(
  p_provider text, p_payment_id text, p_subscription_id uuid, p_amount_cents bigint,
  p_currency text, p_status text, p_period_end timestamptz default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_sub public.subscriptions; v_payment uuid;
begin
  select * into v_sub from public.subscriptions where id = p_subscription_id;
  if not found then raise exception 'subscription_not_found' using errcode = 'P0001'; end if;

  insert into public.payments (subscription_id, owner_id, amount_cents, currency, status, provider, provider_payment_id, paid_at)
  values (v_sub.id, v_sub.owner_id, p_amount_cents, p_currency, p_status, p_provider, p_payment_id,
          case when p_status = 'paid' then now() end)
  on conflict (provider, provider_payment_id) do update
    set status = excluded.status,
        paid_at = coalesce(public.payments.paid_at, excluded.paid_at)
  returning id into v_payment;

  if p_status = 'paid' then
    update public.subscriptions
       set status = 'active', provider = p_provider,
           current_period_end = p_period_end, renews_at = p_period_end, expires_at = null
     where id = v_sub.id;
  end if;
  return v_payment;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rate limiting persistente (partilhado entre instâncias serverless)
-- ---------------------------------------------------------------------------
create or replace function public.check_rate_limit(p_key text, p_max integer, p_window_seconds integer)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_start timestamptz; v_hits integer;
begin
  v_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  insert into public.rate_limits as r (key, window_start, hits) values (p_key, v_start, 1)
  on conflict (key, window_start) do update set hits = r.hits + 1
  returning hits into v_hits;
  if random() < 0.02 then
    delete from public.rate_limits where window_start < now() - interval '2 days';
  end if;
  return v_hits <= p_max;
end;
$$;

-- ---------------------------------------------------------------------------
-- Auditoria imutável
-- ---------------------------------------------------------------------------
create or replace function public.tg_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs_are_immutable' using errcode = '42501';
end;
$$;
create trigger audit_logs_no_update before update or delete on public.audit_logs
  for each row execute function public.tg_audit_immutable();

-- ---------------------------------------------------------------------------
-- Estatísticas (respeitam RLS/permissões; sem dados de outras lojas)
-- ---------------------------------------------------------------------------
create or replace function public.store_dashboard_stats(p_store uuid)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
begin
  if not (public.store_role(p_store) is not null or public.is_superadmin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'products_total', (select count(*) from public.products where store_id = p_store and status <> 'archived'),
    'products_published', (select count(*) from public.products where store_id = p_store and status = 'published'),
    'orders_total', (select count(*) from public.orders where store_id = p_store),
    'orders_pending', (select count(*) from public.orders where store_id = p_store and status = 'pending'),
    'orders_completed', (select count(*) from public.orders where store_id = p_store and status = 'completed'),
    'orders_canceled', (select count(*) from public.orders where store_id = p_store and status = 'canceled'),
    'sales_completed_cents', (select coalesce(sum(total_cents), 0) from public.orders where store_id = p_store and status = 'completed'),
    'pipeline_cents', (select coalesce(sum(total_cents), 0) from public.orders where store_id = p_store and status in ('confirmed', 'preparing', 'shipped')),
    'page_views_30d', (select count(*) from public.analytics_events where store_id = p_store and event_type = 'page_view' and created_at > now() - interval '30 days'),
    'product_views_30d', (select count(*) from public.analytics_events where store_id = p_store and event_type = 'product_view' and created_at > now() - interval '30 days'),
    'order_clicks_30d', (select count(*) from public.analytics_events where store_id = p_store and event_type = 'order_click' and created_at > now() - interval '30 days'),
    'orders_created_30d', (select count(*) from public.orders where store_id = p_store and created_at > now() - interval '30 days'),
    'top_products', coalesce((
      select jsonb_agg(t) from (
        select oi.product_name as name, sum(oi.quantity)::int as quantity, count(distinct oi.order_id)::int as orders
        from public.order_items oi join public.orders o on o.id = oi.order_id
        where o.store_id = p_store and o.status <> 'canceled'
        group by oi.product_name order by sum(oi.quantity) desc limit 5
      ) t), '[]'::jsonb),
    'top_viewed_products', coalesce((
      select jsonb_agg(t) from (
        select p.name, count(*)::int as views
        from public.analytics_events e join public.products p on p.id = e.product_id
        where e.store_id = p_store and e.event_type = 'product_view' and e.created_at > now() - interval '30 days'
        group by p.name order by count(*) desc limit 5
      ) t), '[]'::jsonb),
    'top_referrers', coalesce((
      select jsonb_agg(t) from (
        select referrer_host as host, count(*)::int as visits
        from public.analytics_events
        where store_id = p_store and event_type = 'page_view' and referrer_host is not null
          and created_at > now() - interval '30 days'
        group by referrer_host order by count(*) desc limit 5
      ) t), '[]'::jsonb)
  );
end;
$$;

create or replace function public.platform_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_superadmin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users_total', (select count(*) from public.profiles),
    'users_active', (select count(*) from public.profiles where status = 'active'),
    'users_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'stores_total', (select count(*) from public.stores),
    'stores_published', (select count(*) from public.stores where status = 'published'),
    'stores_suspended', (select count(*) from public.stores where status = 'suspended'),
    'orders_total', (select count(*) from public.orders),
    'plans_total', (select count(*) from public.plans),
    'subscriptions_active', (select count(*) from public.subscriptions where status in ('active', 'trialing')),
    'subscriptions_expired', (select count(*) from public.subscriptions where status in ('expired', 'canceled')),
    'revenue_received', coalesce((
      select jsonb_agg(t) from (
        select currency, sum(amount_cents)::bigint as amount_cents, count(*)::int as payments
        from public.payments where status = 'paid' group by currency
      ) t), '[]'::jsonb),
    'users_growth', coalesce((
      select jsonb_agg(t order by t.day) from (
        select to_char(date_trunc('day', created_at), 'YYYY-MM-DD') as day, count(*)::int as users
        from public.profiles where created_at > now() - interval '30 days' group by 1
      ) t), '[]'::jsonb),
    'recent_failures', (select count(*) from public.audit_logs where result = 'failure' and created_at > now() - interval '7 days')
  );
end;
$$;
