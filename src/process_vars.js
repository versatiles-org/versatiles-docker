
// Used for GitHub Workflow build-single-image.yml

import { argv } from 'node:process';

let args = JSON.parse(argv[2]);
let keys = 'filename,platforms,repo,tag,variants'.split(',');



// cleanup values, set to undefined if not defined
keys.forEach(key => {
	if (typeof args[key] !== 'string') return args[key] = undefined;
	args[key] = args[key].trim();
	let value = args[key].toLowerCase();
	if ((value === '') || (value === 'false')) return args[key] = undefined;
})

// check undefined values
if (!args.filename) throw Error('filename not defined');
args.platforms ??= 'linux/amd64,linux/arm64';
args.repo ??= 'versatiles';
if (!args.tag) throw Error('tag not defined');
args.variants ??= '';

// calc suffixes
let suffixes = args.variants.split(',').map(v => {
	v = v.trim().toLowerCase();
	return v === '' ? '' : '-' + v
})

// calc tags
let tags = new Set();
'versatiles,ghcr.io/versatiles-org'.split(',').forEach(org => {
	suffixes.forEach(suffix => {
		tags.add(`${org}/${args.repo}:latest${suffix}`)
		tags.add(`${org}/${args.repo}:${args.tag}${suffix}`)
	})
})

args.tags = Array.from(tags.values()).join(',')

for (let [key,value] of Object.entries(args)) {
	process.stdout.write(`${key}=${value}\n`)
}
