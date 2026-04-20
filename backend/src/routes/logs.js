const express = require('express');
const esClient = require('../lib/elasticsearch');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter } = require('../middleware/rateLimit');

const router = express.Router();

router.get('/', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const {
    q = '',
    level,
    source,
    from = '0',
    size = '25',
    index = process.env.ELASTIC_INDEX || 'wazuh-alerts-*',
  } = req.query;

  const filters = [];
  if (level) {
    filters.push({ term: { 'rule.level': level } });
  }
  if (source) {
    filters.push({ term: { 'agent.name.keyword': source } });
  }

  const must = q ? [{ query_string: { query: q } }] : [{ match_all: {} }];

  try {
    const response = await esClient.search({
      index,
      from: Math.max(Number(from) || 0, 0),
      size: Math.min(Math.max(Number(size) || 25, 1), 200),
      query: {
        bool: {
          must,
          filter: filters,
        },
      },
      sort: [{ '@timestamp': { order: 'desc' } }],
    });

    const hits = response.hits?.hits || [];

    return res.json({
      total: response.hits?.total?.value || 0,
      results: hits.map((hit) => ({
        id: hit._id,
        index: hit._index,
        ...hit._source,
      })),
    });
  } catch (error) {
    const detail =
      error?.meta?.body?.error?.reason ||
      error?.meta?.body?.error?.type ||
      error?.message ||
      'Unknown Elasticsearch error';

    return res.status(502).json({
      error: 'Failed to query Elasticsearch',
      detail,
    });
  }
});

module.exports = router;
