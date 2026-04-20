const { Client } = require('@elastic/elasticsearch');

const node = process.env.ELASTIC_URL || 'http://localhost:9200';
const username = process.env.ELASTIC_USERNAME;
const password = process.env.ELASTIC_PASSWORD;

const clientOptions = { node };
if (username && password) {
  clientOptions.auth = { username, password };
}

const esClient = new Client(clientOptions);

module.exports = esClient;
