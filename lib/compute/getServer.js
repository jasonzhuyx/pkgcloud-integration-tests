var pkgcloud = require('pkgcloud'),
  logging = require('../common/logging'),
  config = require('../common/config'),
  _ = require('underscore');

var log = logging.getLogger(process.env.PKGCLOUD_LOG_LEVEL || 'debug');

var provider = process.argv[2];

var client = pkgcloud.compute.createClient(config.getConfig(provider, 1));

client.on('log::*', logging.logFunction);

client.getServer(process.argv[3], function (err, server) {
  if (err) {
    log.error(err);
    return;
  }

  log.info(server.toJSON());
});
