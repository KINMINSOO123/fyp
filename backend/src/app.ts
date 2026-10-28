import express from "express";

const app = express();

// Parse incoming JSON request bodies.
app.use(express.json());

// A simple endpoint to check whether the server is running.
app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "smart-bakery-api",
  });
});

export default app;