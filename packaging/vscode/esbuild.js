// @ts-check
const esbuild = require('esbuild');

/** @type {import('esbuild').BuildOptions} */
const buildOptions = {
  entryPoints: ['extension.js'],
  bundle: true,
  outfile: 'dist/extension.js',
  external: ['vscode'],
  format: 'cjs',
  platform: 'node',
  target: 'node18',
  sourcemap: false,
  minify: false,
};

async function main() {
  const watch = process.argv.includes('--watch');

  if (watch) {
    const ctx = await esbuild.context(buildOptions);
    await ctx.watch();
    console.log('Watching for changes...');
  } else {
    await esbuild.build(buildOptions);
    console.log('Build complete: dist/extension.js');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
