import { env } from "@/lib/env";

export interface TenantInfo {
  isStore: boolean;
  slug: string | null;
  customDomain: string | null;
}

const RESERVED_SUBDOMAINS = new Set([
  "www",
  "app",
  "admin",
  "superadmin",
  "api",
  "dashboard",
  "login",
  "register",
  "billing",
  "support",
  "mail",
  "status",
]);

export function extractTenant(hostWithPort: string): TenantInfo {
  const host = hostWithPort.split(":")[0]?.toLowerCase() ?? "";
  const rootDomain = env.NEXT_PUBLIC_ROOT_DOMAIN.toLowerCase();

  // 1. Caso de desenvolvimento local com subdomínio: ex. "minhaloja.localhost"
  if (host.endsWith(".localhost")) {
    const sub = host.slice(0, -".localhost".length);
    if (sub && !RESERVED_SUBDOMAINS.has(sub)) {
      return { isStore: true, slug: sub, customDomain: null };
    }
    return { isStore: false, slug: null, customDomain: null };
  }

  // 2. Localhost direto ou IP de loopback
  if (host === "localhost" || host === "127.0.0.1") {
    return { isStore: false, slug: null, customDomain: null };
  }

  // 3. Subdomínio da plataforma: ex. "minhaloja.lojix.app"
  if (host.endsWith(`.${rootDomain}`)) {
    const sub = host.slice(0, -(rootDomain.length + 1));
    if (sub && !RESERVED_SUBDOMAINS.has(sub)) {
      return { isStore: true, slug: sub, customDomain: null };
    }
    return { isStore: false, slug: null, customDomain: null };
  }

  // 4. Domínio raiz direto (ex.: "lojix.app" ou "www.lojix.app")
  if (host === rootDomain || host === `www.${rootDomain}`) {
    return { isStore: false, slug: null, customDomain: null };
  }

  // 5. Domínio personalizado (ex.: "minhaloja.mz")
  return { isStore: true, slug: null, customDomain: host };
}
