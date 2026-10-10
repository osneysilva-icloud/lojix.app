import { z } from "zod";

const envSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url().default("http://127.0.0.1:54321"),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1).default("dummy-anon-key"),
  SUPABASE_SERVICE_ROLE_KEY: z.string().optional(),
  NEXT_PUBLIC_ROOT_DOMAIN: z.string().default("lojix.app"),
  NEXT_PUBLIC_SITE_PROTOCOL: z.enum(["http", "https"]).default("https"),
  ALLOW_PATH_STORES: z
    .string()
    .optional()
    .transform((val) => val === "true"),
});

export const env = envSchema.parse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  NEXT_PUBLIC_ROOT_DOMAIN: process.env.NEXT_PUBLIC_ROOT_DOMAIN,
  NEXT_PUBLIC_SITE_PROTOCOL: process.env.NEXT_PUBLIC_SITE_PROTOCOL,
  ALLOW_PATH_STORES: process.env.ALLOW_PATH_STORES,
});
