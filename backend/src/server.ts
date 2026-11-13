import app from "./app.js";
import {env} from "./config/env.js";

app.listen(env.port, "0.0.0.0", (error?: Error) => {
  if (error) {
    console.error(`Smart Bakery API could not start: ${error.message}`);
    process.exitCode = 1;
    return;
  }
  console.log(`Smart Bakery API running on port http://localhost:${env.port}`);
});

