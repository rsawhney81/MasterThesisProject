const express = require('express');

const app = express();

const port = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'api',
    environment: process.env.AZURE_ENVIRONMENT || process.env.AZURE_ENV_NAME || 'unknown'
  });
});

app.get('/', (req, res) => {
  res.status(200).send('ecomm-api');
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`API listening on port ${port}`);
});
