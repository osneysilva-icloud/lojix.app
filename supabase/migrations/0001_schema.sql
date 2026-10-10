-- =============================================================================
-- LOJIX — 0001_schema.sql
-- Esquema principal. Dinheiro em unidades menores (centavos) como bigint.
-- Todos os recursos de loja têm store_id e chaves compostas (id, store_id)
-- para garantir consistência de tenant ao nível da base de dados.
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Planos
-- ---------------------------------------------------------------------------
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_-]{2,40}$'),
  name text not null check (char_length(name) between 2 and 80),
  description text not null default '',
  price_cents bigint not null default 0 check (price_cents >= 0),
  currency text not null default 'MZN' check (currency ~ '^[A-Z]{3}$'),
  billing_period text not null default 'monthly'
    check (billing_period in ('free', 'monthly', 'quarterly', 'yearly', 'one_time')),
  max_stores integer check (max_stores is null or max_stores >= 0),          -- null = ilimitado
  max_products integer check (max_products is null or max_products >= 0),    -- null = ilimitado
  storage_limit_mb integer check (storage_limit_mb is null or storage_limit_mb >= 0),
  template_keys text[] not null default '{}',
  features jsonb not null default '{}'::jsonb,
  is_active boolean not null default false,
  is_default boolean not null default false,  -- plano atribuído no registo
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index plans_single_default on public.plans (is_default) where is_default;
create trigger plans_updated_at before update on public.plans
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Perfis (1:1 com auth.users). O papel de plataforma é controlado só no servidor.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  avatar_url text,
  locale text not null default 'pt-MZ',
  preferences jsonb not null default '{}'::jsonb,
  platform_role text not null default 'user' check (platform_role in ('user', 'superadmin')),
  status text not null default 'active' check (status in ('active', 'suspended')),
  suspended_reason text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index profiles_email_lower_key on public.profiles (lower(email));
create index profiles_role_idx on public.profiles (platform_role) where platform_role <> 'user';
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.admin_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (char_length(note) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index admin_notes_user_idx on public.admin_notes (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Assinaturas e pagamentos (sem fornecedor de pagamentos integrado)
-- ---------------------------------------------------------------------------
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  plan_id uuid not null references public.plans (id),
  status text not null
    check (status in ('trialing', 'active', 'past_due', 'canceled', 'expired', 'incomplete')),
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  started_at timestamptz not null default now(),
  current_period_end timestamptz,
  renews_at timestamptz,
  expires_at timestamptz,
  canceled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index subscriptions_one_live_per_owner on public.subscriptions (owner_id)
  where status in ('trialing', 'active', 'past_due');
create unique index subscriptions_provider_ref_key on public.subscriptions (provider, provider_subscription_id)
  where provider_subscription_id is not null;
create index subscriptions_plan_idx on public.subscriptions (plan_id);
create trigger subscriptions_updated_at before update on public.subscriptions
  for each row execute function public.set_updated_at();

create table public.subscription_events (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  from_plan_id uuid references public.plans (id),
  to_plan_id uuid references public.plans (id),
  actor_id uuid references public.profiles (id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index subscription_events_sub_idx on public.subscription_events (subscription_id, created_at desc);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid references public.subscriptions (id) on delete set null,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  amount_cents bigint not null check (amount_cents >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null check (status in ('pending', 'paid', 'failed', 'refunded', 'canceled')),
  provider text not null,
  provider_payment_id text not null,
  paid_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,   -- nunca guardar segredos aqui
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_payment_id)
);
create index payments_owner_idx on public.payments (owner_id, created_at desc);
create trigger payments_updated_at before update on public.payments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Lojas
-- ---------------------------------------------------------------------------
create table public.reserved_slugs (
  slug text primary key check (slug = lower(slug))
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete restrict,
  name text not null check (char_length(name) between 2 and 80),
  slug text not null
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$' and slug !~ '--'),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'suspended', 'archived')),
  suspended_reason text,
  template_key text not null default 'physical' check (template_key in ('physical', 'fashion', 'digital')),
  currency text not null default 'MZN' check (currency ~ '^[A-Z]{3}$'),
  published_theme jsonb,          -- snapshot público da personalização (ver publish_store_settings)
  published_at timestamptz,
  theme_published_at timestamptz,
  slug_changed_at timestamptz,
  next_order_number integer not null default 1001,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);
create unique index stores_slug_key on public.stores (slug);
create index stores_owner_idx on public.stores (owner_id);
create index stores_status_idx on public.stores (status);
create trigger stores_updated_at before update on public.stores
  for each row execute function public.set_updated_at();

create table public.store_slug_history (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  old_slug text not null,
  changed_at timestamptz not null default now()
);
create index store_slug_history_slug_idx on public.store_slug_history (old_slug);

create table public.store_members (
  store_id uuid not null references public.stores (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'staff')),
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);
create index store_members_user_idx on public.store_members (user_id);
create unique index store_members_single_owner on public.store_members (store_id) where role = 'owner';

create table public.media_files (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  kind text not null check (kind in
    ('logo', 'favicon', 'banner', 'cover', 'product', 'category', 'page', 'digital')),
  bucket text not null check (bucket in ('store-public', 'store-private')),
  path text not null unique,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  original_name text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, store_id),
  check ((kind = 'digital') = (bucket = 'store-private'))
);
create index media_files_store_idx on public.media_files (store_id, kind);

create table public.store_settings (
  store_id uuid primary key references public.stores (id) on delete cascade,
  description text not null default '',
  primary_color text not null default '#4f46e5' check (primary_color ~ '^#[0-9a-fA-F]{6}$'),
  secondary_color text not null default '#0f172a' check (secondary_color ~ '^#[0-9a-fA-F]{6}$'),
  button_color text not null default '#4f46e5' check (button_color ~ '^#[0-9a-fA-F]{6}$'),
  font_key text not null default 'sans' check (font_key in ('sans', 'serif', 'rounded', 'mono')),
  logo_media_id uuid,
  favicon_media_id uuid,
  banner_media_id uuid,
  cover_media_id uuid,
  banner_title text not null default '',
  banner_subtitle text not null default '',
  contact_email text,
  phone text,
  whatsapp_number text check (whatsapp_number is null or whatsapp_number ~ '^[1-9][0-9]{7,14}$'),
  address text not null default '',
  location_url text,
  business_hours text not null default '',
  social_links jsonb not null default '{}'::jsonb,
  delivery_info text not null default '',
  returns_policy text not null default '',
  payment_methods text[] not null default '{}',
  delivery_enabled boolean not null default true,
  delivery_fee_cents bigint check (delivery_fee_cents is null or delivery_fee_cents >= 0),
  footer_text text not null default '',
  home_sections jsonb not null default
    '[{"key":"banner","enabled":true},{"key":"categories","enabled":true},{"key":"featured","enabled":true},{"key":"products","enabled":true},{"key":"about","enabled":false},{"key":"contact","enabled":true}]'::jsonb,
  seo_title text,
  seo_description text,
  meta_pixel_id text check (meta_pixel_id is null or meta_pixel_id ~ '^[0-9]{8,20}$'),
  updated_at timestamptz not null default now(),
  foreign key (logo_media_id, store_id) references public.media_files (id, store_id) on delete set null (logo_media_id),
  foreign key (favicon_media_id, store_id) references public.media_files (id, store_id) on delete set null (favicon_media_id),
  foreign key (banner_media_id, store_id) references public.media_files (id, store_id) on delete set null (banner_media_id),
  foreign key (cover_media_id, store_id) references public.media_files (id, store_id) on delete set null (cover_media_id)
);
create trigger store_settings_updated_at before update on public.store_settings
  for each row execute function public.set_updated_at();

-- Domínios próprios (preparado para versões futuras; não ativo na v1)
create table public.store_domains (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  domain text not null check (domain = lower(domain) and domain ~ '^[a-z0-9.-]{4,253}$'),
  status text not null default 'pending' check (status in ('pending', 'verified', 'failed')),
  verification_token text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index store_domains_domain_key on public.store_domains (domain);
create index store_domains_store_idx on public.store_domains (store_id);

-- ---------------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  slug text not null check (slug ~ '^[a-z0-9][a-z0-9-]{0,78}$'),
  description text not null default '',
  image_media_id uuid,
  position integer not null default 0,
  is_featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id),
  unique (store_id, slug),
  foreign key (image_media_id, store_id) references public.media_files (id, store_id) on delete set null (image_media_id)
);
create trigger categories_updated_at before update on public.categories
  for each row execute function public.set_updated_at();

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 160),
  slug text not null check (slug ~ '^[a-z0-9][a-z0-9-]{0,118}$'),
  short_description text not null default '' check (char_length(short_description) <= 300),
  description text not null default '' check (char_length(description) <= 20000),
  product_type text not null default 'physical' check (product_type in ('physical', 'digital', 'service')),
  price_cents bigint not null check (price_cents >= 0),
  sale_price_cents bigint check (sale_price_cents is null or (sale_price_cents >= 0 and sale_price_cents < price_cents)),
  currency text not null default 'MZN' check (currency ~ '^[A-Z]{3}$'),
  sku text check (sku is null or char_length(sku) <= 64),
  track_stock boolean not null default false,
  stock_quantity integer check (stock_quantity is null or stock_quantity >= 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  is_featured boolean not null default false,
  weight_grams integer check (weight_grams is null or weight_grams >= 0),
  length_cm numeric(8, 2) check (length_cm is null or length_cm >= 0),
  width_cm numeric(8, 2) check (width_cm is null or width_cm >= 0),
  height_cm numeric(8, 2) check (height_cm is null or height_cm >= 0),
  service_duration_minutes integer check (service_duration_minutes is null or service_duration_minutes > 0),
  option_definitions jsonb not null default '[]'::jsonb,       -- [{"name":"Cor","values":["Preto"]}]
  customization_options jsonb not null default '[]'::jsonb,    -- [{"label":"Nome","type":"text","required":false}]
  digital_media_id uuid,
  digital_delivery_notes text not null default '',
  seo_title text check (seo_title is null or char_length(seo_title) <= 70),
  seo_description text check (seo_description is null or char_length(seo_description) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id),
  unique (store_id, slug),
  foreign key (digital_media_id, store_id) references public.media_files (id, store_id) on delete set null (digital_media_id)
);
create index products_store_status_idx on public.products (store_id, status, created_at desc);
create index products_store_featured_idx on public.products (store_id) where is_featured and status = 'published';
create index products_name_search_idx on public.products (store_id, lower(name));
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  product_id uuid not null,
  sku text check (sku is null or char_length(sku) <= 64),
  option_values jsonb not null,                              -- {"Cor":"Preto","Tamanho":"42"}
  price_cents bigint check (price_cents is null or price_cents >= 0),
  stock_quantity integer check (stock_quantity is null or stock_quantity >= 0),
  is_active boolean not null default true,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id),
  unique (id, product_id),
  unique (product_id, option_values),
  foreign key (product_id, store_id) references public.products (id, store_id) on delete cascade
);
create index product_variants_product_idx on public.product_variants (product_id, position);
create trigger product_variants_updated_at before update on public.product_variants
  for each row execute function public.set_updated_at();

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  product_id uuid not null,
  variant_id uuid,
  media_id uuid not null,
  alt_text text not null default '' check (char_length(alt_text) <= 200),
  position integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, store_id),
  foreign key (product_id, store_id) references public.products (id, store_id) on delete cascade,
  foreign key (variant_id, product_id) references public.product_variants (id, product_id) on delete cascade,
  foreign key (media_id, store_id) references public.media_files (id, store_id) on delete cascade
);
create index product_images_product_idx on public.product_images (product_id, position);
create unique index product_images_one_primary on public.product_images (product_id)
  where is_primary and variant_id is null;

create table public.product_categories (
  store_id uuid not null,
  product_id uuid not null,
  category_id uuid not null,
  primary key (product_id, category_id),
  foreign key (product_id, store_id) references public.products (id, store_id) on delete cascade,
  foreign key (category_id, store_id) references public.categories (id, store_id) on delete cascade
);
create index product_categories_category_idx on public.product_categories (category_id);

create table public.pages (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  kind text not null default 'custom'
    check (kind in ('about', 'contact', 'faq', 'shipping', 'returns', 'privacy', 'terms', 'custom')),
  slug text not null check (slug ~ '^[a-z0-9][a-z0-9-]{0,78}$'),
  title text not null check (char_length(title) between 1 and 160),
  content text not null default '' check (char_length(content) <= 50000),
  status text not null default 'draft' check (status in ('draft', 'published')),
  show_in_menu boolean not null default false,
  show_in_footer boolean not null default true,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, slug)
);
create trigger pages_updated_at before update on public.pages
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Clientes e encomendas
-- ---------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  phone text not null check (phone ~ '^[0-9]{7,15}$'),
  email text,
  province text,
  city text,
  notes text not null default '' check (char_length(notes) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id),
  unique (store_id, phone)
);
create trigger customers_updated_at before update on public.customers
  for each row execute function public.set_updated_at();

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9_-]{3,32}$'),
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value bigint not null check (discount_value > 0),
  min_order_cents bigint check (min_order_cents is null or min_order_cents >= 0),
  max_uses integer check (max_uses is null or max_uses > 0),
  used_count integer not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, store_id),
  unique (store_id, code),
  check (discount_type <> 'percent' or discount_value <= 100)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  order_number text not null,
  customer_id uuid,
  customer_name text not null,
  customer_phone text not null,
  province text,
  city text,
  neighborhood text,
  address text,
  notes text not null default '' check (char_length(notes) <= 2000),
  internal_notes text not null default '' check (char_length(internal_notes) <= 2000),
  delivery_method text not null default 'to_confirm' check (delivery_method in ('delivery', 'pickup', 'to_confirm')),
  payment_method text,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'preparing', 'shipped', 'completed', 'canceled')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid', 'refunded')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  subtotal_cents bigint not null check (subtotal_cents >= 0),
  discount_cents bigint not null default 0 check (discount_cents >= 0),
  delivery_fee_cents bigint check (delivery_fee_cents is null or delivery_fee_cents >= 0),
  total_cents bigint not null check (total_cents >= 0),
  coupon_id uuid,
  access_token text not null unique
    default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  whatsapp_opened_at timestamptz,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id),
  unique (store_id, order_number),
  foreign key (customer_id, store_id) references public.customers (id, store_id) on delete set null (customer_id),
  foreign key (coupon_id, store_id) references public.coupons (id, store_id) on delete set null (coupon_id)
);
create index orders_store_created_idx on public.orders (store_id, created_at desc);
create index orders_store_status_idx on public.orders (store_id, status);
create index orders_customer_idx on public.orders (customer_id);
create index orders_phone_idx on public.orders (store_id, customer_phone);
create trigger orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  order_id uuid not null,
  product_id uuid,
  variant_id uuid,
  product_name text not null,           -- snapshot
  product_type text not null,           -- snapshot
  variant_label text,                   -- snapshot, ex.: "Cor: Preto / Tamanho: 42"
  sku text,
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  quantity integer not null check (quantity between 1 and 99),
  line_total_cents bigint not null check (line_total_cents >= 0),
  customization jsonb,
  created_at timestamptz not null default now(),
  foreign key (order_id, store_id) references public.orders (id, store_id) on delete cascade,
  foreign key (product_id, store_id) references public.products (id, store_id) on delete set null (product_id),
  foreign key (variant_id, store_id) references public.product_variants (id, store_id) on delete set null (variant_id)
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_product_idx on public.order_items (product_id);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  order_id uuid not null,
  from_status text,
  to_status text not null,
  changed_by uuid references public.profiles (id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  foreign key (order_id, store_id) references public.orders (id, store_id) on delete cascade
);
create index order_status_history_order_idx on public.order_status_history (order_id, created_at);

-- ---------------------------------------------------------------------------
-- Analytics, auditoria, configurações globais, rate limit
-- ---------------------------------------------------------------------------
create table public.analytics_events (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores (id) on delete cascade,
  event_type text not null
    check (event_type in ('page_view', 'product_view', 'order_click', 'order_created')),
  product_id uuid references public.products (id) on delete set null,
  path text check (path is null or char_length(path) <= 300),
  referrer_host text check (referrer_host is null or char_length(referrer_host) <= 120),
  session_id text check (session_id is null or char_length(session_id) <= 64),
  created_at timestamptz not null default now()
);
create index analytics_events_store_idx on public.analytics_events (store_id, event_type, created_at desc);
create index analytics_events_product_idx on public.analytics_events (product_id) where product_id is not null;

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id) on delete set null,
  actor_email text,
  action text not null,
  resource_type text not null,
  resource_id text,
  store_id uuid,
  result text not null default 'success' check (result in ('success', 'denied', 'failure')),
  metadata jsonb not null default '{}'::jsonb,   -- nunca guardar segredos/palavras-passe
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_id, created_at desc);
create index audit_logs_resource_idx on public.audit_logs (resource_type, resource_id);

create table public.platform_settings (
  key text primary key check (key ~ '^[a-z0-9_.]{2,80}$'),
  value jsonb not null,
  is_public boolean not null default false,
  updated_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now()
);
create trigger platform_settings_updated_at before update on public.platform_settings
  for each row execute function public.set_updated_at();

create table public.rate_limits (
  key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (key, window_start)
);
