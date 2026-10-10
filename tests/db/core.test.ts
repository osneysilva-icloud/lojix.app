import type { PGlite } from "@electric-sql/pglite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { as, assignPlan, createStore, createTestDb, createUser, expectDenied, makeSuperadmin } from "./harness";

let db: PGlite;
beforeAll(async () => {
  db = await createTestDb();
});
afterAll(async () => {
  await db.close();
});

const authed = (uid: string) => ({ role: "authenticated" as const, uid });

describe("registo e perfis", () => {
  it("cria perfil (papel 'user') e subscrição gratuita ativa ao registar", async () => {
    const uid = await createUser(db, "Maria");
    const p = await db.query<{ platform_role: string; status: string; full_name: string }>(
      "select platform_role, status, full_name from profiles where id = $1", [uid]);
    expect(p.rows[0]).toMatchObject({ platform_role: "user", status: "active", full_name: "Maria" });
    const s = await db.query<{ code: string; status: string }>(
      "select pl.code, s.status from subscriptions s join plans pl on pl.id = s.plan_id where s.owner_id = $1", [uid]);
    expect(s.rows[0]).toEqual({ code: "free", status: "active" });
  });

  it("[14] utilizador comum NÃO consegue promover-se a superadmin nem reativar-se", async () => {
    const uid = await createUser(db);
    await expectDenied(
      as(db, authed(uid), () => db.query("update profiles set platform_role = 'superadmin' where id = $1", [uid])),
      /permission denied/i);
    await expectDenied(
      as(db, authed(uid), () => db.query("update profiles set status = 'active', suspended_reason = null where id = $1", [uid])),
      /permission denied/i);
    await expectDenied(
      as(db, authed(uid), () => db.query("insert into profiles (id, email, platform_role) values (gen_random_uuid(), 'x@x.test', 'superadmin')")),
      /permission denied/i);
    const r = await db.query<{ platform_role: string }>("select platform_role from profiles where id = $1", [uid]);
    expect(r.rows[0]?.platform_role).toBe("user");
  });

  it("utilizador pode editar campos públicos do próprio perfil, mas não o de outros", async () => {
    const a = await createUser(db, "A");
    const b = await createUser(db, "B");
    await as(db, authed(a), () => db.query("update profiles set full_name = 'A Novo' where id = $1", [a]));
    const upd = await as(db, authed(a), () => db.query("update profiles set full_name = 'Hack' where id = $1 returning id", [b]));
    expect(upd.rows).toHaveLength(0);
    const seen = await as(db, authed(a), () => db.query("select id from profiles"));
    expect(seen.rows.map((r) => (r as { id: string }).id)).toEqual([a]);
  });

  it("apenas service_role atribui papel de superadmin; is_superadmin() reflete-o", async () => {
    const uid = await createUser(db);
    const before = await as(db, authed(uid), () => db.query<{ v: boolean }>("select is_superadmin() as v"));
    expect(before.rows[0]?.v).toBe(false);
    await makeSuperadmin(db, uid);
    const after = await as(db, authed(uid), () => db.query<{ v: boolean }>("select is_superadmin() as v"));
    expect(after.rows[0]?.v).toBe(true);
  });

  it("superadmin suspenso perde privilégios", async () => {
    const uid = await createUser(db);
    await makeSuperadmin(db, uid);
    await as(db, { role: "service_role" }, () => db.query("update profiles set status = 'suspended' where id = $1", [uid]));
    const r = await as(db, authed(uid), () => db.query<{ v: boolean }>("select is_superadmin() as v"));
    expect(r.rows[0]?.v).toBe(false);
  });
});

describe("[15] limites de plano aplicados no servidor (triggers)", () => {
  it("plano gratuito: apenas 1 loja", async () => {
    const uid = await createUser(db);
    await createStore(db, uid, "primeiraloja");
    await expectDenied(createStore(db, uid, "segundaloja"), /plan_limit_stores/);
  });

  it("modelo 'fashion' não permitido no plano gratuito", async () => {
    const uid = await createUser(db);
    await expectDenied(createStore(db, uid, "modaloja", { template: "fashion" }), /plan_template_not_allowed/);
  });

  it("limite de produtos por loja", async () => {
    const uid = await createUser(db);
    await assignPlan(db, uid, { code: "t-products", max_stores: 5, max_products: 2 });
    const store = await createStore(db, uid, "limiteprod");
    for (const n of ["p1", "p2"]) {
      await as(db, authed(uid), () =>
        db.query("insert into products (store_id, name, slug, price_cents) values ($1, $2, $2, 100)", [store, n]));
    }
    await expectDenied(
      as(db, authed(uid), () => db.query("insert into products (store_id, name, slug, price_cents) values ($1, 'p3', 'p3', 100)", [store])),
      /plan_limit_products/);
  });

  it("limite de armazenamento", async () => {
    const uid = await createUser(db);
    await assignPlan(db, uid, { code: "t-storage", max_stores: 5, storage_mb: 1 });
    const store = await createStore(db, uid, "limitestor");
    const ins = (size: number, p: string) =>
      as(db, authed(uid), () => db.query(
        "insert into media_files (store_id, kind, bucket, path, mime_type, size_bytes, created_by) values ($1, 'product', 'store-public', $2, 'image/webp', $3, $4)",
        [store, p, size, uid]));
    await ins(900_000, `${store}/product/a.webp`);
    await expectDenied(ins(300_000, `${store}/product/b.webp`), /plan_limit_storage/);
  });

  it("Meta Pixel só com funcionalidade ativa no plano", async () => {
    const uid = await createUser(db);
    const store = await createStore(db, uid, "pixelloja");
    await expectDenied(
      as(db, authed(uid), () => db.query("update store_settings set meta_pixel_id = '123456789012345' where store_id = $1", [store])),
      /plan_feature_meta_pixel/);
    await assignPlan(db, uid, { code: "t-pixel", max_stores: 5, features: { meta_pixel: true } });
    await as(db, authed(uid), () => db.query("update store_settings set meta_pixel_id = '123456789012345' where store_id = $1", [store]));
    await expectDenied(
      as(db, authed(uid), () => db.query("update store_settings set meta_pixel_id = 'alert(1)' where store_id = $1", [store])),
      /check constraint/i);
  });

  it("plano expirado volta aos limites do plano predefinido", async () => {
    const uid = await createUser(db);
    await assignPlan(db, uid, { code: "t-expiring", max_stores: 9 });
    await db.query("update subscriptions set expires_at = now() - interval '1 day' where owner_id = $1", [uid]);
    await createStore(db, uid, "expirada1");
    await expectDenied(createStore(db, uid, "expirada2"), /plan_limit_stores/);
  });
});

describe("[3][4] slugs: duplicados, reservados, formato, alteração controlada", () => {
  it("rejeita slug duplicado", async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    await createStore(db, a, "salaodudas");
    await expectDenied(createStore(db, b, "salaodudas"), /slug_taken|duplicate key/);
  });

  it("bloqueia nomes reservados", async () => {
    const u = await createUser(db);
    for (const slug of ["www", "admin", "api", "app", "dashboard", "login", "register", "support", "billing", "superadmin"]) {
      await expectDenied(createStore(db, u, slug), /slug_reserved/);
    }
  });

  it("rejeita formatos inválidos (maiúsculas, hífens duplos, curto, caracteres especiais)", async () => {
    const u = await createUser(db);
    for (const slug of ["SalaoDudas", "a--b", "ab", "-abc", "abc-", "sal ao", "salão", "a_b_c"]) {
      await expectDenied(createStore(db, u, slug), /check constraint|slug_invalid/i);
    }
  });

  it("slug_availability devolve o motivo correto", async () => {
    const u = await createUser(db);
    await createStore(db, u, "disponivel1");
    const q = (s: string) => db.query<{ r: string }>("select slug_availability($1) as r", [s]).then((x) => x.rows[0]?.r);
    expect(await q("disponivel1")).toBe("taken");
    expect(await q("www")).toBe("reserved");
    expect(await q("Bad Slug")).toBe("invalid");
    expect(await q("livre-123")).toBe("available");
  });

  it("proprietário não altera o slug diretamente; só pelo fluxo controlado, com histórico e cooldown", async () => {
    const u = await createUser(db);
    const other = await createUser(db);
    const store = await createStore(db, u, "nomeantigo");
    await expectDenied(
      as(db, authed(u), () => db.query("update stores set slug = 'outronome1' where id = $1", [store])),
      /permission denied/i);
    // primeira alteração permitida
    await as(db, authed(u), () => db.query("select change_store_slug($1, 'nomenovo1')", [store]));
    const s = await db.query<{ slug: string }>("select slug from stores where id = $1", [store]);
    expect(s.rows[0]?.slug).toBe("nomenovo1");
    // slug antigo fica indisponível para outros (evita sequestro)
    await expectDenied(createStore(db, other, "nomeantigo"), /slug_taken/);
    // cooldown de 30 dias
    await expectDenied(
      as(db, authed(u), () => db.query("select change_store_slug($1, 'nomenovo2')", [store])),
      /slug_change_cooldown/);
    // outro utilizador não pode alterar o slug
    await expectDenied(
      as(db, authed(other), () => db.query("select change_store_slug($1, 'hijack123')", [store])),
      /forbidden/);
  });

  it("alterar o nome comercial não altera o endereço", async () => {
    const u = await createUser(db);
    const store = await createStore(db, u, "mantemslug");
    await as(db, authed(u), () => db.query("update stores set name = 'Novo Nome' where id = $1", [store]));
    const r = await db.query<{ slug: string; name: string }>("select slug, name from stores where id = $1", [store]);
    expect(r.rows[0]).toEqual({ slug: "mantemslug", name: "Novo Nome" });
  });
});

describe("estados da loja e suspensão", () => {
  it("proprietário publica/despublica/arquiva mas não suspende nem levanta suspensão", async () => {
    const u = await createUser(db);
    const store = await createStore(db, u, "estadosloja");
    await as(db, authed(u), () => db.query("update stores set status = 'published' where id = $1", [store]));
    const pub = await db.query<{ published_at: string | null }>("select published_at from stores where id = $1", [store]);
    expect(pub.rows[0]?.published_at).not.toBeNull();
    await as(db, authed(u), () => db.query("update stores set status = 'draft' where id = $1", [store]));
    await expectDenied(
      as(db, authed(u), () => db.query("update stores set status = 'suspended' where id = $1", [store])),
      /forbidden_store_status/);
    await expectDenied(
      as(db, authed(u), () => db.query("update stores set owner_id = gen_random_uuid() where id = $1", [store])),
      /permission denied/i);

    const admin = await createUser(db);
    await makeSuperadmin(db, admin);
    await as(db, authed(admin), () =>
      db.query("update stores set status = 'suspended', suspended_reason = 'abuso' where id = $1", [store]));
    await expectDenied(
      as(db, authed(u), () => db.query("update stores set status = 'published' where id = $1", [store])),
      /forbidden_store_status/);
    await as(db, authed(admin), () => db.query("update stores set status = 'draft', suspended_reason = null where id = $1", [store]));
  });

  it("resolve_store_state distingue desconhecida/rascunho/publicada/suspensa", async () => {
    const u = await createUser(db);
    const store = await createStore(db, u, "resolvestate");
    const st = (s: string) => as(db, { role: "anon" }, () =>
      db.query<{ r: string }>("select resolve_store_state($1) as r", [s]).then((x) => x.rows[0]?.r));
    expect(await st("naoexiste1")).toBe("unknown");
    expect(await st("resolvestate")).toBe("draft");
    await as(db, authed(u), () => db.query("update stores set status = 'published' where id = $1", [store]));
    expect(await st("resolvestate")).toBe("published");
    await as(db, { role: "service_role" }, () => db.query("update stores set status = 'suspended' where id = $1", [store]));
    expect(await st("resolvestate")).toBe("suspended");
  });

  it("loja de utilizador suspenso deixa de ser pública", async () => {
    const u = await createUser(db);
    const store = await createStore(db, u, "donosuspenso", { publish: true });
    const count = () => as(db, { role: "anon" }, () =>
      db.query<{ n: number }>("select count(*)::int as n from stores where id = $1", [store]).then((x) => x.rows[0]?.n));
    expect(await count()).toBe(1);
    await as(db, { role: "service_role" }, () => db.query("update profiles set status = 'suspended' where id = $1", [u]));
    expect(await count()).toBe(0);
  });
});

describe("papéis de loja e dados de plataforma", () => {
  it("utilizador comum não gere planos nem configurações globais; superadmin gere", async () => {
    const u = await createUser(db);
    const admin = await createUser(db);
    await makeSuperadmin(db, admin);
    await expectDenied(
      as(db, authed(u), () => db.query("insert into plans (code, name) values ('hack', 'Hack')")),
      /row-level security/i);
    const upd = await as(db, authed(u), () => db.query("update plans set price_cents = 1 returning id"));
    expect(upd.rows).toHaveLength(0);
    await as(db, authed(admin), () => db.query("insert into plans (code, name, price_cents) values ('novo', 'Novo', 5000)"));
    await expectDenied(
      as(db, authed(u), () => db.query("update platform_settings set value = '\"X\"' where key = 'platform.name'")),
      /row-level security|permission/i);
  });

  it("anónimos só veem planos ativos e configurações públicas", async () => {
    const plans = await as(db, { role: "anon" }, () => db.query<{ code: string }>("select code from plans"));
    expect(plans.rows.map((r) => r.code)).toContain("free");
    expect(plans.rows.map((r) => r.code)).not.toContain("pro");
    const priv = await as(db, { role: "anon" }, () => db.query("select key from platform_settings where key = 'platform.publication'"));
    expect(priv.rows).toHaveLength(0);
  });

  it("auditoria é imutável e inacessível a utilizadores comuns", async () => {
    const u = await createUser(db);
    await as(db, { role: "service_role" }, () =>
      db.query("insert into audit_logs (action, resource_type, metadata) values ('teste', 'x', '{}')"));
    const seen = await as(db, authed(u), () => db.query("select id from audit_logs"));
    expect(seen.rows).toHaveLength(0);
    await expectDenied(
      as(db, { role: "service_role" }, () => db.query("delete from audit_logs")),
      /audit_logs_are_immutable/);
    await expectDenied(
      as(db, authed(u), () => db.query("insert into audit_logs (action, resource_type) values ('x', 'y')")),
      /permission denied/i);
  });

  it("rate limit persistente bloqueia depois do máximo", async () => {
    const key = `test:${Date.now()}`;
    const hit = () => as(db, { role: "service_role" }, () =>
      db.query<{ ok: boolean }>("select check_rate_limit($1, 3, 60) as ok", [key]).then((x) => x.rows[0]?.ok));
    expect([await hit(), await hit(), await hit(), await hit()]).toEqual([true, true, true, false]);
    await expectDenied(
      as(db, authed(await createUser(db)), () => db.query("select check_rate_limit('x', 1, 1)")),
      /permission denied/i);
  });
});
