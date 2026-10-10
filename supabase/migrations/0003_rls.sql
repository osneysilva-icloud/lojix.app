-- =============================================================================
-- LOJIX — 0003_rls.sql
-- Row Level Security + grants. Princípio: negar por omissão; conceder o mínimo.
-- service_role (bypass RLS) é usado apenas no servidor, nunca no cliente.
-- =============================================================================

-- Remove privilégios herdados por omissão
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Funções usadas por políticas/triggers executados com o papel do chamador
grant execute on function
  public.is_privileged_db_role(), public.is_superadmin(), public.store_role(uuid),
  public.is_store_member(uuid), public.can_manage_store(uuid), public.store_is_public(uuid),
  public.product_is_public(uuid)
to anon, authenticated;

grant execute on function public.resolve_store_state(text) to anon, authenticated;
grant execute on function
  public.slug_availability(text, uuid), public.change_store_slug(uuid, text),
  public.publish_store_settings(uuid), public.touch_last_seen(),
  public.store_dashboard_stats(uuid), public.platform_stats(),
  public.storage_usage_bytes(uuid)
to authenticated;
-- RPCs só para o servidor (service_role): criação de encomendas, rate limit, eventos de pagamento
grant execute on function
  public.create_whatsapp_order(uuid, jsonb), public.record_whatsapp_click(text),
  public.check_rate_limit(text, integer, integer),
  public.apply_payment_event(text, text, uuid, bigint, text, text, timestamptz),
  public.build_store_theme(uuid), public.owner_plan(uuid), public.plan_feature(uuid, text)
to service_role;

-- ---------------------------------------------------------------------------
-- Grants de tabela
-- ---------------------------------------------------------------------------
grant select on public.profiles to authenticated;
grant update (full_name, avatar_url, locale, preferences) on public.profiles to authenticated;

grant select, insert on public.admin_notes to authenticated;

grant select on public.plans to anon, authenticated;
grant insert, update, delete on public.plans to authenticated;

grant select, insert, update, delete on public.subscriptions to authenticated;
grant select on public.subscription_events to authenticated;
grant select on public.payments to authenticated;

grant select on public.stores to anon, authenticated;
grant insert (owner_id, name, slug, template_key, currency) on public.stores to authenticated;
grant update (name, status, template_key, suspended_reason) on public.stores to authenticated;

grant select on public.store_slug_history to authenticated;
grant select on public.store_members to authenticated;
grant select on public.store_domains to authenticated;

grant select on public.store_settings to authenticated;
grant update (
  description, primary_color, secondary_color, button_color, font_key,
  logo_media_id, favicon_media_id, banner_media_id, cover_media_id,
  banner_title, banner_subtitle, contact_email, phone, whatsapp_number, address, location_url,
  business_hours, social_links, delivery_info, returns_policy, payment_methods,
  delivery_enabled, delivery_fee_cents, footer_text, home_sections, seo_title, seo_description,
  meta_pixel_id
) on public.store_settings to authenticated;

grant select on public.media_files to anon, authenticated;
grant insert, delete on public.media_files to authenticated;

grant select on public.categories, public.products, public.product_variants,
  public.product_images, public.product_categories, public.pages to anon, authenticated;
grant insert, update, delete on public.categories, public.products, public.product_variants,
  public.product_images, public.product_categories, public.pages to authenticated;

grant select on public.customers to authenticated;
grant update (name, email, province, city, notes) on public.customers to authenticated;

grant select, insert, update, delete on public.coupons to authenticated;

grant select on public.orders, public.order_items, public.order_status_history to authenticated;
grant update (status, payment_status, internal_notes) on public.orders to authenticated;

grant select on public.analytics_events to authenticated;
grant select on public.audit_logs to authenticated;

grant select on public.platform_settings to anon, authenticated;
grant insert, update on public.platform_settings to authenticated;

-- ---------------------------------------------------------------------------
-- Ativar RLS em todas as tabelas
-- ---------------------------------------------------------------------------
alter table public.plans enable row level security;
alter table public.profiles enable row level security;
alter table public.admin_notes enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_events enable row level security;
alter table public.payments enable row level security;
alter table public.reserved_slugs enable row level security;
alter table public.stores enable row level security;
alter table public.store_slug_history enable row level security;
alter table public.store_members enable row level security;
alter table public.media_files enable row level security;
alter table public.store_settings enable row level security;
alter table public.store_domains enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_images enable row level security;
alter table public.product_categories enable row level security;
alter table public.pages enable row level security;
alter table public.customers enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;
alter table public.analytics_events enable row level security;
alter table public.audit_logs enable row level security;
alter table public.platform_settings enable row level security;
alter table public.rate_limits enable row level security;

-- ---------------------------------------------------------------------------
-- Políticas
-- ---------------------------------------------------------------------------
-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_superadmin());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- admin_notes
create policy admin_notes_superadmin on public.admin_notes for all to authenticated
  using (public.is_superadmin()) with check (public.is_superadmin() and author_id = auth.uid());

-- plans
create policy plans_select_anon on public.plans for select to anon
  using (is_active);
create policy plans_select_authenticated on public.plans for select to authenticated
  using (
    is_active or public.is_superadmin()
    or exists (select 1 from public.subscriptions s where s.plan_id = plans.id and s.owner_id = auth.uid())
  );
create policy plans_write on public.plans for all to authenticated
  using (public.is_superadmin()) with check (public.is_superadmin());

-- subscriptions / events / payments
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (owner_id = auth.uid() or public.is_superadmin());
create policy subscriptions_write on public.subscriptions for all to authenticated
  using (public.is_superadmin()) with check (public.is_superadmin());
create policy subscription_events_select on public.subscription_events for select to authenticated
  using (owner_id = auth.uid() or public.is_superadmin());
create policy payments_select on public.payments for select to authenticated
  using (owner_id = auth.uid() or public.is_superadmin());

-- stores
create policy stores_select_anon on public.stores for select to anon
  using (public.store_is_public(id));
create policy stores_select_authenticated on public.stores for select to authenticated
  using (
    public.store_is_public(id)
    or (owner_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'active'))
    or public.is_store_member(id)
    or public.is_superadmin()
  );
create policy stores_insert on public.stores for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'active')
  );
create policy stores_update on public.stores for update to authenticated
  using (public.can_manage_store(id) or public.is_superadmin())
  with check (public.can_manage_store(id) or public.is_superadmin());

create policy store_slug_history_select on public.store_slug_history for select to authenticated
  using (public.can_manage_store(store_id) or public.is_superadmin());
create policy store_members_select on public.store_members for select to authenticated
  using (user_id = auth.uid() or public.is_store_member(store_id) or public.is_superadmin());
create policy store_domains_select on public.store_domains for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());

create policy store_settings_select on public.store_settings for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());
create policy store_settings_update on public.store_settings for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

-- media_files
create policy media_files_select on public.media_files for select to anon, authenticated
  using (
    public.is_store_member(store_id) or public.is_superadmin()
    or (bucket = 'store-public' and public.store_is_public(store_id))
  );
create policy media_files_insert on public.media_files for insert to authenticated
  with check (public.can_manage_store(store_id) and created_by = auth.uid());
create policy media_files_delete on public.media_files for delete to authenticated
  using (public.can_manage_store(store_id));

-- catálogo
create policy categories_select on public.categories for select to anon, authenticated
  using (public.is_store_member(store_id) or public.is_superadmin() or public.store_is_public(store_id));
create policy categories_insert on public.categories for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy categories_update on public.categories for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy categories_delete on public.categories for delete to authenticated
  using (public.can_manage_store(store_id));

create policy products_select on public.products for select to anon, authenticated
  using (
    public.is_store_member(store_id) or public.is_superadmin()
    or (status = 'published' and public.store_is_public(store_id))
  );
create policy products_insert on public.products for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy products_update on public.products for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy products_delete on public.products for delete to authenticated
  using (public.can_manage_store(store_id));

create policy product_variants_select on public.product_variants for select to anon, authenticated
  using (
    public.is_store_member(store_id) or public.is_superadmin()
    or (is_active and public.product_is_public(product_id))
  );
create policy product_variants_insert on public.product_variants for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy product_variants_update on public.product_variants for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy product_variants_delete on public.product_variants for delete to authenticated
  using (public.can_manage_store(store_id));

create policy product_images_select on public.product_images for select to anon, authenticated
  using (public.is_store_member(store_id) or public.is_superadmin() or public.product_is_public(product_id));
create policy product_images_insert on public.product_images for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy product_images_update on public.product_images for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy product_images_delete on public.product_images for delete to authenticated
  using (public.can_manage_store(store_id));

create policy product_categories_select on public.product_categories for select to anon, authenticated
  using (public.is_store_member(store_id) or public.is_superadmin() or public.product_is_public(product_id));
create policy product_categories_insert on public.product_categories for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy product_categories_delete on public.product_categories for delete to authenticated
  using (public.can_manage_store(store_id));

create policy pages_select on public.pages for select to anon, authenticated
  using (
    public.is_store_member(store_id) or public.is_superadmin()
    or (status = 'published' and public.store_is_public(store_id))
  );
create policy pages_insert on public.pages for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy pages_update on public.pages for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy pages_delete on public.pages for delete to authenticated
  using (public.can_manage_store(store_id));

-- clientes e encomendas (nunca públicos)
create policy customers_select on public.customers for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());
create policy customers_update on public.customers for update to authenticated
  using (public.is_store_member(store_id)) with check (public.is_store_member(store_id));

create policy coupons_select on public.coupons for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());
create policy coupons_insert on public.coupons for insert to authenticated
  with check (public.can_manage_store(store_id));
create policy coupons_update on public.coupons for update to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
create policy coupons_delete on public.coupons for delete to authenticated
  using (public.can_manage_store(store_id));

create policy orders_select on public.orders for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());
create policy orders_update on public.orders for update to authenticated
  using (public.is_store_member(store_id)) with check (public.is_store_member(store_id));
create policy order_items_select on public.order_items for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());
create policy order_status_history_select on public.order_status_history for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());

create policy analytics_events_select on public.analytics_events for select to authenticated
  using (public.is_store_member(store_id) or public.is_superadmin());

create policy audit_logs_select on public.audit_logs for select to authenticated
  using (public.is_superadmin());

create policy platform_settings_select on public.platform_settings for select to anon, authenticated
  using (is_public or public.is_superadmin());
create policy platform_settings_insert on public.platform_settings for insert to authenticated
  with check (public.is_superadmin());
create policy platform_settings_update on public.platform_settings for update to authenticated
  using (true) with check (public.is_superadmin());
-- reserved_slugs e rate_limits: sem políticas (acesso apenas via funções SECURITY DEFINER / service_role)
