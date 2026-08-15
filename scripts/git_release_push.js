const { execSync } = require('child_process');

function run(cmd) {
  console.log(`> ${cmd}`);
  try {
    const out = execSync(cmd, { encoding: 'utf8' });
    console.log(out);
  } catch (e) {
    console.log(e.stdout || e.stderr || e.message);
  }
}

run('git add .');
run('git commit -m "Release Siya Solar Staff v1.0.3"');
run('git tag -a v1.0.3 -m "Siya Solar Staff v1.0.3 Build 4"');
run('git push origin main --tags');
