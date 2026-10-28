import { supabaseAdmin } from "../config/supabase.js";

async function checkDatabase(): Promise<void> {
  const { data, error } = await supabaseAdmin
    .from("bread_categories")
    .select("id, name")
    .limit(5);

  if (error) {
    console.error("Database check failed:", error.message);
    process.exitCode = 1;
    return;
  }

  console.log("Database connection successful.");
  console.table(data);

  if( data.length === 0 ) {
    console.log("The query succeeded, but no bread categories were returned.");
  }
}

checkDatabase().catch((error: unknown) => {
  console.error(
    "Database check failed:",
    error instanceof Error ? error.message : "Unknown error",
  );
  process.exitCode = 1;
})