'use strict';
const {initializeApp} = require('firebase-admin/app');
initializeApp();
Object.assign(exports, require('./throne'));
Object.assign(exports, require('./wallet'), require('./purchases'), require('./box_wallet'), require('./refunds'));