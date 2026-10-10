-- =============================================================================
-- LOJIX â€” 0001_schema.sql
-- Esquema principal. Dinheiro em unidades menores (centavos) como bigint.
-- Todos os recursos de loja tÃªm store_id e chaves compostas (id, store_id)
-- para garantir consistÃªncia de tenant ao nÃ­vel da base de dados.
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
  is_default boolean not null default false,  -- plano atribuÃ­do no registo
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index plans_single_default on public.plans (is_default) where is_default;
create trigger plans_updated_at before update on public.plans
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Perfis (1:1 com auth.users). O papel de plataforma Ã© controlado sÃ³ no servidor.
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
  published_theme jsonb,          -- snapshot pÃºblico da personalizaÃ§Ã£o (ver publish_store_settings)
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

-- DomÃ­nios prÃ³prios (preparado para versÃµes futuras; nÃ£o ativo na v1)
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
-- CatÃ¡logo
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
-- Analytics, auditoria, configuraÃ§Ãµes globais, rate limit
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
-- =============================================================================
-- LOJIX â€” 0002_functions.sql
-- FunÃ§Ãµes auxiliares, triggers de integridade/seguranÃ§a, limites de plano e RPCs.
-- Erros de negÃ³cio usam errcode P0001 com mensagem = cÃ³digo (ex.: plan_limit_products).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Auxiliares de identidade/permissÃµes
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

-- Impede alteraÃ§Ãµes de papel/estado/e-mail por utilizadores comuns (defesa em profundidade;
-- as grants por coluna jÃ¡ o impedem).
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

-- Invoker (nÃ£o security definer): current_user reflete o papel real do chamador.
-- FunÃ§Ãµes SECURITY DEFINER internas (change_store_slug, publish_store_settings) executam como
-- dono e sÃ£o consideradas fiÃ¡veis.
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
-- BEFORE para poder ajustar slug_changed_at (executa depois da validaÃ§Ã£o por ordem alfabÃ©tica)
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
-- Integridade de catÃ¡logo
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

-- Bloqueia remoÃ§Ã£o de categorias com produtos (validaÃ§Ã£o de dependÃªncias)
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
-- PublicaÃ§Ã£o da personalizaÃ§Ã£o (snapshot pÃºblico)
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
-- Assinaturas: histÃ³rico e eventos de pagamento (apenas servidor/service_role)
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

-- SÃ³ deve ser chamada por um webhook cuja assinatura jÃ¡ foi verificada no servidor.
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
-- Rate limiting persistente (partilhado entre instÃ¢ncias serverless)
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
-- Auditoria imutÃ¡vel
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
-- EstatÃ­sticas (respeitam RLS/permissÃµes; sem dados de outras lojas)
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
-- =============================================================================
-- LOJIX â€” 0003_rls.sql
-- Row Level Security + grants. PrincÃ­pio: negar por omissÃ£o; conceder o mÃ­nimo.
-- service_role (bypass RLS) Ã© usado apenas no servidor, nunca no cliente.
-- =============================================================================

-- Remove privilÃ©gios herdados por omissÃ£o
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- FunÃ§Ãµes usadas por polÃ­ticas/triggers executados com o papel do chamador
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
-- RPCs sÃ³ para o servidor (service_role): criaÃ§Ã£o de encomendas, rate limit, eventos de pagamento
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
-- PolÃ­ticas
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

-- catÃ¡logo
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

-- clientes e encomendas (nunca pÃºblicos)
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
-- reserved_slugs e rate_limits: sem polÃ­ticas (acesso apenas via funÃ§Ãµes SECURITY DEFINER / service_role)
-- =============================================================================
-- LOJIX â€” 0004_storage.sql
-- Buckets e polÃ­ticas de Storage. Estrutura de caminhos: {store_id}/{tipo}/{ficheiro}
--  - store-public : imagens (logÃ³tipos, banners, produtos, categorias, pÃ¡ginas). Leitura pÃºblica por URL.
--  - store-private: ficheiros digitais. Sem acesso pÃºblico; descarga sÃ³ por URL assinada
--                   emitida pelo servidor apÃ³s validar a encomenda paga.
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

-- Extrai o store_id do primeiro segmento do caminho; devolve null se invÃ¡lido
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

-- Sem polÃ­tica de SELECT para anon: o acesso pÃºblico faz-se por URL do bucket pÃºblico.
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
-- =============================================================================
-- LOJIX â€” 0005_reference_data.sql
-- Dados de referÃªncia (nÃ£o sÃ£o dados de demonstraÃ§Ã£o): palavras reservadas,
-- planos iniciais e configuraÃ§Ãµes globais. PreÃ§os/limites sÃ£o SUGESTÃ•ES editÃ¡veis
-- no painel de superadmin. Planos Pro e Business ficam INATIVOS (sem preÃ§o definido)
-- atÃ© o superadmin os configurar e ativar.
-- =============================================================================

insert into public.reserved_slugs (slug) values
  ('www'), ('admin'), ('administrator'), ('api'), ('app'), ('dashboard'), ('login'), ('logout'),
  ('register'), ('signup'), ('signin'), ('support'), ('billing'), ('superadmin'), ('root'),
  ('mail'), ('email'), ('smtp'), ('imap'), ('pop'), ('ftp'), ('cdn'), ('static'), ('assets'),
  ('media'), ('files'), ('images'), ('img'), ('docs'), ('blog'), ('help'), ('status'),
  ('staging'), ('dev'), ('test'), ('demo'), ('beta'), ('preview'), ('internal'), ('system'),
  ('security'), ('abuse'), ('postmaster'), ('webmaster'), ('hostmaster'), ('lojix'),
  ('lojixapp'), ('store'), ('stores'), ('shop'), ('loja'), ('lojas'), ('checkout'), ('cart'),
  ('account'), ('accounts'), ('auth'), ('oauth'), ('sso'), ('dns'), ('vpn'), ('git'),
  ('studio'), ('console'), ('panel'), ('portal'), ('pricing'), ('features'), ('templates'),
  ('about'), ('contact'), ('faq'), ('terms'), ('privacy'), ('refund'), ('refund-policy'),
  ('legal'), ('press'), ('careers'), ('jobs'), ('partners'), ('affiliates'), ('pay'),
  ('payments'), ('mpesa'), ('emola'), ('whatsapp'), ('null'), ('undefined'), ('localhost'),
  ('home'), ('welcome'), ('new'), ('settings'), ('profile'), ('users'), ('user'), ('web'),
  ('ads'), ('analytics'), ('metrics'), ('monitor'), ('health'), ('ping'), ('webhooks'),
  ('hooks'), ('notifications'), ('noreply'), ('info'), ('sales'), ('ns1'), ('ns2'), ('mx')
on conflict do nothing;

insert into public.plans
  (code, name, description, price_cents, currency, billing_period, max_stores, max_products,
   storage_limit_mb, template_keys, features, is_active, is_default, sort_order)
values
  ('free', 'Gratuito', 'Para comeÃ§ar a vender com o essencial.', 0, 'MZN', 'free', 1, 20, 100,
   array['physical', 'digital'],
   '{"meta_pixel": false, "advanced_stats": false, "custom_domain": false, "marketing_tools": false}'::jsonb,
   true, true, 10),
  ('pro', 'Pro', 'Mais produtos, mais modelos e estatÃ­sticas adicionais. (PreÃ§o por definir.)', 0, 'MZN', 'monthly',
   3, 500, 2048, array['physical', 'fashion', 'digital'],
   '{"meta_pixel": true, "advanced_stats": true, "custom_domain": false, "marketing_tools": true}'::jsonb,
   false, false, 20),
  ('business', 'Business', 'Limites superiores para operaÃ§Ãµes maiores. (PreÃ§o por definir.)', 0, 'MZN', 'monthly',
   10, null, 10240, array['physical', 'fashion', 'digital'],
   '{"meta_pixel": true, "advanced_stats": true, "custom_domain": false, "marketing_tools": true}'::jsonb,
   false, false, 30)
on conflict (code) do nothing;

insert into public.platform_settings (key, value, is_public) values
  ('platform.name', '"LOJIX"', true),
  ('platform.support_email', '""', true),
  ('platform.contacts', '{"phone": "", "whatsapp": "", "address": ""}', true),
  ('platform.default_currency', '"MZN"', true),
  ('platform.global_message', '{"enabled": false, "level": "info", "text": ""}', true),
  ('platform.features', '{"meta_pixel": true, "analytics": true, "digital_products": true}', true),
  ('platform.store_templates', '{"physical": {"enabled": true}, "fashion": {"enabled": true}, "digital": {"enabled": true}}', true),
  ('platform.publication', '{"allow_registrations": true, "allow_store_publishing": true}', false)
on conflict (key) do nothing;
