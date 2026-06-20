const fs = require('fs');
console.log(fs.readFileSync('earth.frag', 'utf8').substring(0, 100));
