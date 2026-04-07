const express = require('express');

const app = express();
const port = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'frontend',
    environment: process.env.AZURE_ENVIRONMENT || process.env.AZURE_ENV_NAME || 'unknown'
  });
});

app.get('/', (req, res) => {
  const apiBaseUrl = process.env.API_BASE_URL || '';
  res.status(200).type('html').send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>E-commerce Frontend</title>
</head>
<body>
  <h1>E-commerce Frontend</h1>
  <p>API base URL: <code>${apiBaseUrl || '(not set)'}</code></p>
  <p>Try the API health endpoint at <code>${apiBaseUrl}/health</code></p>
</body>
</html>`);
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Frontend listening on port ${port}`);
});
