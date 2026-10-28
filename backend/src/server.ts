import app from "./app.js";
import {env} from "./config/env.js";

app.listen(env.port, () => {
  console.log(`Smart Bakery API running on port http://localhost:${env.port}`);
});

