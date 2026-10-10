export type PlatformRole = "user" | "superadmin";
export type UserStatus = "active" | "suspended";

export interface Profile {
  id: string;
  email: string;
  full_name: string;
  avatar_url: string | null;
  locale: string;
  preferences: Record<string, unknown>;
  platform_role: PlatformRole;
  status: UserStatus;
  suspended_reason: string | null;
  last_seen_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Plan {
  id: string;
  code: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_period: "free" | "monthly" | "quarterly" | "yearly" | "one_time";
  max_stores: number | null;
  max_products: number | null;
  storage_limit_mb: number | null;
  template_keys: string[];
  features: {
    meta_pixel?: boolean;
    advanced_stats?: boolean;
    custom_domain?: boolean;
    marketing_tools?: boolean;
    [key: string]: unknown;
  };
  is_active: boolean;
  is_default: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

export type StoreStatus = "draft" | "published" | "suspended" | "archived";

export interface Store {
  id: string;
  owner_id: string;
  name: string;
  slug: string;
  status: StoreStatus;
  suspended_reason: string | null;
  template_key: string;
  currency: string;
  slug_changed_at: string | null;
  published_at: string | null;
  published_theme: Record<string, unknown> | null;
  theme_published_at: string | null;
  next_order_number: number;
  created_at: string;
  updated_at: string;
}

export interface StoreSettings {
  store_id: string;
  description: string | null;
  primary_color: string;
  secondary_color: string;
  button_color: string;
  font_key: string;
  logo_media_id: string | null;
  favicon_media_id: string | null;
  banner_media_id: string | null;
  cover_media_id: string | null;
  banner_title: string | null;
  banner_subtitle: string | null;
  contact_email: string | null;
  phone: string | null;
  whatsapp_number: string | null;
  address: string | null;
  location_url: string | null;
  business_hours: string | null;
  social_links: Record<string, string>;
  delivery_info: string | null;
  returns_policy: string | null;
  payment_methods: string[];
  delivery_enabled: boolean;
  delivery_fee_cents: number;
  footer_text: string | null;
  home_sections: Record<string, unknown>[];
  seo_title: string | null;
  seo_description: string | null;
  meta_pixel_id: string | null;
  updated_at: string;
}

export interface Product {
  id: string;
  store_id: string;
  name: string;
  slug: string;
  description: string | null;
  price_cents: number;
  compare_at_price_cents: number | null;
  currency: string;
  status: "draft" | "published" | "archived";
  track_stock: boolean;
  stock_quantity: number | null;
  is_digital: boolean;
  digital_media_id: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
}
