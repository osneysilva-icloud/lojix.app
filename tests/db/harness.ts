import { PGlite } from "@electric-sql/pglite";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

/**
 * Harness de testes de integração: executa as migrations REAIS (supabase/migrations) num Postgres
 * em WASM (PGlite), com um pequeno "shim" dos esquemas/papéis do Supabase (auth, storage,
 * anon/authenticated/service_role). Permite testar RLS, grants, triggers e RPCs sem Docker.
 *
 * Limitação: não testa o Supabase Auth/Storage/PostgREST reais (ver docs/TESTING.md).
 */

const SHIM = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create schema storage;
create table storage.buckets (
  id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text, owner uuid, metadata jsonb
);
alter table storage.objects enable row level security;

grant usage on schema public, auth, storage to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
grant all on all tables in schema storage to anon, authenticated, service_role;
`;

export type Who = { role: "anon" | "authenticated" | "service_role"; uid?: string };

export async function createTestDb(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(SHIM);
  const dir = path.resolve(__dirname, "../../supabase/migrations");
  const files = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort();
  for (const f of files) {
    try {
      await db.exec(readFileSync(path.join(dir, f), "utf8"));
    } catch (e) {
      throw new Error(`Falha na migration ${f}: ${(e as Error).message}`);
    }
  }
  return db;
}

/** Executa `fn` com o papel/utilizador indicado (equivalente ao JWT do PostgREST). */
export async function as<T>(db: PGlite, who: Who, fn: () => Promise<T>): Promise<T> {
  await db.exec(`select set_config('request.jwt.claim.sub', '${who.uid ?? ""}', false)`);
  await db.exec(`set role ${who.role}`);
  try {
    return await fn();
  } finally {
    await db.exec("reset role");
    await db.exec("select set_config('request.jwt.claim.sub', '', false)");
  }
}

let counter = 0;
export async function createUser(db: PGlite, name = "Utilizador"): Promise<string> {
  counter += 1;
  const email = `user${counter}-${Date.now()}@example.test`;
  const r = await db.query<{ id: string }>(
    "insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id",
    [email, JSON.stringify({ full_name: name })],
  );
  return r.rows[0]!.id;
}

export async function makeSuperadmin(db: PGlite, uid: string): Promise<void> {
  await as(db, { role: "service_role" }, () =>
    db.query("update profiles set platform_role = 'superadmin' where id = $1", [uid]),
  );
}

export async function createStore(
  db: PGlite,
  owner: string,
  slug: string,
  extra: { template?: string; publish?: boolean } = {},
): Promise<string> {
  const id = await as(db, { role: "authenticated", uid: owner }, async () => {
    const r = await db.query<{ id: string }>(
      "insert into stores (owner_id, name, slug, template_key) values ($1, $2, $3, $4) returning id",
      [owner, `Loja ${slug}`, slug, extra.template ?? "physical"],
    );
    return r.rows[0]!.id;
  });
  if (extra.publish) {
    await as(db, { role: "authenticated", uid: owner }, () =>
      db.query("update stores set status = 'published' where id = $1", [id]),
    );
  }
  return id;
}

/** Plano de teste atribuído ao utilizador (via service_role, como faria o painel de superadmin). */
export async function assignPlan(
  db: PGlite,
  owner: string,
  limits: { code: string; max_stores?: number | null; max_products?: number | null; storage_mb?: number | null; features?: object },
): Promise<void> {
  await db.query(
    `insert into plans (code, name, max_stores, max_products, storage_limit_mb, template_keys, features, is_active)
     values ($1, $1, $2, $3, $4, array['physical','fashion','digital'], $5::jsonb, true)
     on conflict (code) do update set max_stores = excluded.max_stores, max_products = excluded.max_products,
       storage_limit_mb = excluded.storage_limit_mb, features = excluded.features`,
    [limits.code, limits.max_stores ?? null, limits.max_products ?? null, limits.storage_mb ?? null, JSON.stringify(limits.features ?? {})],
  );
  await db.query(
    `update subscriptions set plan_id = (select id from plans where code = $2) where owner_id = $1 and status = 'active'`,
    [owner, limits.code],
  );
}

export async function expectDenied(promise: Promise<unknown>, pattern: RegExp): Promise<void> {
  try {
    await promise;
  } catch (e) {
    const msg = (e as Error).message;
    if (!pattern.test(msg)) throw new Error(`Erro inesperado: "${msg}" (esperado ${pattern})`);
    return;
  }
  throw new Error(`Esperava-se uma recusa (${pattern}), mas a operação foi permitida.`);
}
