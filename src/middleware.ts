import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";
import { extractTenant } from "@/lib/tenant";

export async function middleware(request: NextRequest) {
  const host = request.headers.get("host") || "";
  const { pathname } = request.nextUrl;

  // 1. Atualizar sessão Supabase e obter utilizador
  const { response, user, supabase } = await updateSession(request);

  // 2. Extrair tenant por subdomínio ou domínio próprio
  const tenant = extractTenant(host);

  // Se for acesso a loja via subdomínio (ex: calçados.lojix.app ou loja.localhost:3000)
  if (tenant.isStore && tenant.slug) {
    const url = request.nextUrl.clone();
    // Reescreve internamente para a rota dinâmica da loja: /store/:slug/*
    url.pathname = `/store/${tenant.slug}${pathname === "/" ? "" : pathname}`;
    const rewriteResponse = NextResponse.rewrite(url, {
      request: {
        headers: new Headers(request.headers),
      },
    });
    rewriteResponse.headers.set("x-tenant-slug", tenant.slug);
    return rewriteResponse;
  }

  // Se for domínio personalizado
  if (tenant.isStore && tenant.customDomain) {
    const url = request.nextUrl.clone();
    url.pathname = `/store/domain/${tenant.customDomain}${pathname === "/" ? "" : pathname}`;
    const rewriteResponse = NextResponse.rewrite(url, {
      request: {
        headers: new Headers(request.headers),
      },
    });
    rewriteResponse.headers.set("x-custom-domain", tenant.customDomain);
    return rewriteResponse;
  }

  // 3. Plataforma principal: Proteção de rotas autenticadas
  if (pathname.startsWith("/dashboard")) {
    if (!user) {
      const loginUrl = request.nextUrl.clone();
      loginUrl.pathname = "/login";
      loginUrl.searchParams.set("next", pathname);
      return NextResponse.redirect(loginUrl);
    }
  }

  if (pathname.startsWith("/superadmin")) {
    if (!user) {
      const loginUrl = request.nextUrl.clone();
      loginUrl.pathname = "/login";
      loginUrl.searchParams.set("next", pathname);
      return NextResponse.redirect(loginUrl);
    }

    // Verificar se utilizador tem permissões de superadmin
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role, status")
      .eq("id", user.id)
      .single();

    if (!profile || profile.platform_role !== "superadmin" || profile.status !== "active") {
      const forbiddenUrl = request.nextUrl.clone();
      forbiddenUrl.pathname = "/dashboard";
      return NextResponse.redirect(forbiddenUrl);
    }
  }

  // Redirecionar utilizadores já autenticados que acedam a /login ou /register
  if (user && (pathname === "/login" || pathname === "/register")) {
    const dashboardUrl = request.nextUrl.clone();
    dashboardUrl.pathname = "/dashboard";
    return NextResponse.redirect(dashboardUrl);
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
