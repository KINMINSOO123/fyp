const portText = process.env.PORT ?? "3000";

if (!/^\d+$/.test(portText)) {
  throw new Error("PORT must be a whole number.");
}

const port = Number(portText);

if(!Number.isInteger(port) || port < 0 || port > 65535) {
  throw new Error("PORT must be a whole number between 0 and 65535.");
}

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

export const env = {
  port,
  supabaseUrl: requireEnv("SUPABASE_URL"),
  supabaseServiceRoleKey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
};
