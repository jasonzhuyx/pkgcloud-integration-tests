var pkgcloud = require('pkgcloud'),
  logging = require('../../../common/logging'),
  config = require('../../../common/config'),
  _ = require('underscore');

var log = logging.getLogger(process.env.PKGCLOUD_LOG_LEVEL || 'debug');

var client = pkgcloud.providers.rackspace.database.createClient(config.getConfig('rackspace'));

client.on('log::*', logging.logFunction);

client.getFlavors(function (err, flavors) {
  if (err) {
    log.error(err);
    return;
  }

  flavors = flavors.sort(function(a, b) {
    return a.ram >= b.ram;
  });

  flavors.forEach(function (flavor) {
    log.info(flavor.id);
    log.info('\t' + flavor.name);
  });
});
