-- =============================================================================
-- LOJIX — 0005_reference_data.sql
-- Dados de referência (não são dados de demonstração): palavras reservadas,
-- planos iniciais e configurações globais. Preços/limites são SUGESTÕES editáveis
-- no painel de superadmin. Planos Pro e Business ficam INATIVOS (sem preço definido)
-- até o superadmin os configurar e ativar.
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
  ('free', 'Gratuito', 'Para começar a vender com o essencial.', 0, 'MZN', 'free', 1, 20, 100,
   array['physical', 'digital'],
   '{"meta_pixel": false, "advanced_stats": false, "custom_domain": false, "marketing_tools": false}'::jsonb,
   true, true, 10),
  ('pro', 'Pro', 'Mais produtos, mais modelos e estatísticas adicionais. (Preço por definir.)', 0, 'MZN', 'monthly',
   3, 500, 2048, array['physical', 'fashion', 'digital'],
   '{"meta_pixel": true, "advanced_stats": true, "custom_domain": false, "marketing_tools": true}'::jsonb,
   false, false, 20),
  ('business', 'Business', 'Limites superiores para operações maiores. (Preço por definir.)', 0, 'MZN', 'monthly',
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
