import { createClient } from "@supabase/supabase-js";

interface BootstrapOptions {
  verifyOnly?: boolean;
  rotatePassword?: boolean;
}

function parseArgs(): BootstrapOptions {
  const args = process.argv.slice(2);
  return {
    verifyOnly: args.includes("--verify"),
    rotatePassword: args.includes("--rotate-password"),
  };
}

function getEnvOrThrow(name: string): string {
  const val = process.env[name]?.trim();
  if (!val) {
    throw new Error(`Variável de ambiente obrigatória não definida: ${name}`);
  }
  return val;
}

export async function runBootstrap(opts: BootstrapOptions = parseArgs()): Promise<void> {
  const supabaseUrl = getEnvOrThrow("NEXT_PUBLIC_SUPABASE_URL");
  const serviceRoleKey = getEnvOrThrow("SUPABASE_SERVICE_ROLE_KEY");
  const email = getEnvOrThrow("SUPERADMIN_EMAIL").toLowerCase();
  const password = process.env.SUPERADMIN_PASSWORD?.trim();

  if (!opts.verifyOnly && (!password || password.length < 8)) {
    throw new Error("SUPERADMIN_PASSWORD tem de ter pelo menos 8 caracteres.");
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  console.log(`[Superadmin] A verificar utilizador ${email}...`);

  // 1. Procurar utilizador existente
  const { data: userListData, error: listError } = await supabase.auth.admin.listUsers();
  if (listError) {
    throw new Error(`Falha ao consultar auth.users: ${listError.message}`);
  }

  const existingUser = userListData.users.find((u) => u.email?.toLowerCase() === email);

  // Modo --verify
  if (opts.verifyOnly) {
    if (!existingUser) {
      console.error(`[Superadmin:Verify] Utilizador ${email} NÃO existe no Supabase Auth.`);
      process.exitCode = 1;
      return;
    }

    const { data: profile, error: profError } = await supabase
      .from("profiles")
      .select("id, platform_role, status, email")
      .eq("id", existingUser.id)
      .single();

    if (profError || !profile) {
      console.error(`[Superadmin:Verify] Perfil não encontrado para ${email}: ${profError?.message}`);
      process.exitCode = 1;
      return;
    }

    if (profile.platform_role !== "superadmin" || profile.status !== "active") {
      console.error(
        `[Superadmin:Verify] Utilizador encontrado mas não é superadmin ativo (role: ${profile.platform_role}, status: ${profile.status}).`,
      );
      process.exitCode = 1;
      return;
    }

    console.log(`[Superadmin:Verify] OK! ${email} está ativo como superadmin.`);
    return;
  }

  // Modo --rotate-password
  if (opts.rotatePassword) {
    if (!existingUser) {
      throw new Error(`Não é possível rodar password: ${email} não existe no Supabase Auth.`);
    }

    console.log(`[Superadmin] A atualizar password de ${email}...`);
    const { error: updateAuthError } = await supabase.auth.admin.updateUserById(existingUser.id, {
      password: password!,
    });
    if (updateAuthError) {
      throw new Error(`Falha ao rodar password: ${updateAuthError.message}`);
    }

    console.log(`[Superadmin] Password de ${email} atualizada com sucesso.`);
    return;
  }

  // Modo criação / bootstrap padrão
  let userId: string;

  if (existingUser) {
    userId = existingUser.id;
    console.log(`[Superadmin] Utilizador já existe no Supabase Auth (id: ${userId}).`);
    // Atualiza palavra-passe se fornecida
    if (password) {
      const { error: updErr } = await supabase.auth.admin.updateUserById(userId, {
        password,
        email_confirm: true,
      });
      if (updErr) {
        throw new Error(`Falha ao sincronizar palavra-passe: ${updErr.message}`);
      }
    }
  } else {
    console.log(`[Superadmin] A criar utilizador no Supabase Auth...`);
    const { data: newUser, error: createError } = await supabase.auth.admin.createUser({
      email,
      password: password!,
      email_confirm: true,
      user_metadata: { full_name: "Superadmin" },
    });

    if (createError || !newUser.user) {
      throw new Error(`Falha ao criar utilizador: ${createError?.message}`);
    }
    userId = newUser.user.id;
    console.log(`[Superadmin] Utilizador criado (id: ${userId}).`);
  }

  // Assegurar papel superadmin e status active no perfil
  console.log(`[Superadmin] A promover perfil para platform_role='superadmin'...`);
  const { error: profileError } = await supabase
    .from("profiles")
    .update({
      platform_role: "superadmin",
      status: "active",
      suspended_reason: null,
    })
    .eq("id", userId);

  if (profileError) {
    throw new Error(`Falha ao promover perfil: ${profileError.message}`);
  }

  console.log(`[Superadmin] Concluído! ${email} é agora superadmin ativo do LOJIX.`);
}

if (process.argv[1]?.includes("bootstrap-superadmin")) {
  runBootstrap().catch((err: Error) => {
    console.error(`[Superadmin] Erro: ${err.message}`);
    process.exit(1);
  });
}
