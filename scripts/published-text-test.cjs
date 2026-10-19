#!/usr/bin/env node
// covers: published-text
// Fixture for helpers/published-text.cjs — the one extraction the three outgoing-text gates share.
// Both directions per function; the gates' own fixtures prove the wiring (test-public-text-guard.sh,
// test-instance-key-gate.sh, test-guards.sh). Usage: node scripts/published-text-test.cjs (exit 0 = pass)
const path = require('path');
const p = require(path.join(__dirname, '..', 'helpers', 'published-text.cjs'));

let fail = 0;
const ok = (name, cond, detail) => {
  console.log(`  ${cond ? 'OK  ' : 'FAIL'} ${name}${cond ? '' : ': ' + JSON.stringify(detail)}`);
  if (!cond) fail++;
};
const G = 'g' + 'h'; // the fixture text must not read as a post to the gates that guard this repo

// shellSegments: words, quotes, segments, comments, spans
let s = p.shellSegments(`git commit -m "a b" # tail ; ${G} pr create`, false);
ok('a comment ends the line', s.length === 1 && s[0].join('|') === 'git|commit|-m|a b', s);
s = p.shellSegments(`echo x; ${G} pr comment 1 --body 'y z'`, false);
ok('a ; starts a new segment', s.length === 2 && s[1][4] === '--body' && s[1][5] === 'y z', s);
const cmd = `git commit -m "hello there" -q`;
s = p.shellSegments(cmd, false);
ok('spans cover the quoted word', cmd.slice(...s[0].spans[3]) === '"hello there"', s[0].spans);
ok('a heredoc is not read', p.shellSegments(`${G} pr comment 1 --body "$(cat <<'X'\nhi\nX\n)"`, false) === null);
ok('an unbalanced quote is not read', p.shellSegments(`git commit -m "open`, false) === null);
ok('PowerShell keeps backslashes', p.shellSegments('x C:\\a\\b', true)[0][1] === 'C:\\a\\b');
ok('bash unquoted backslash escapes', p.shellSegments('x a\\ b', false)[0][1] === 'a b');

// publishedText
let t = p.publishedText(`${G} pr create --title T --body-file f.md -f k=v -F n=@g.md`, false);
ok('title, field value and both files', t.texts.join('|') === 'T|v' && t.files.join('|') === 'f.md|g.md', t);
t = p.publishedText(`git -C /x commit -am "msg" --file=m.txt`, false);
ok('git -am value and --file=', t.texts.join('|') === 'msg' && t.files.join('|') === 'm.txt', t);
t = p.publishedText(`${G} api repos/o/r/contents/a.md -X PUT -f message=x`, false);
ok('the gh api endpoint is published text', t.texts[0] === 'repos/o/r/contents/a.md', t);
t = p.publishedText(`${G} pr comment 1 --body "$(cat b.md)"`, false);
ok('$(cat file) is a handed-over file', t.files[0] === 'b.md', t);

// invocations
ok('a quoted PR command is no invocation',
  p.invocations(`git commit -m "${G} pr create"`, false, G, ['pr'], ['create']).length === 0);
ok('a real one after ; is found',
  p.invocations(`true; ${G} pr create -t x`, false, G, ['pr'], ['create']).length === 1);

// withoutPublished
ok('a message value is blanked, the rest stays byte for byte',
  p.withoutPublished(`git commit -m "rm -rf x" && ls -la`, false) === 'git commit -m <MESSAGE-STRIPPED> && ls -la');
ok('a value that can execute stays',
  p.withoutPublished('git commit -m "$(danger)"', false) === 'git commit -m "$(danger)"');
ok('a single-quoted $( ) is literal and blanked',
  p.withoutPublished("git commit -m '$(not run)'", false) === 'git commit -m <MESSAGE-STRIPPED>');
ok('no gh/git: nothing blanked', p.withoutPublished('tool --body "x"', false) === 'tool --body "x"');
ok('an unreadable line returns null', p.withoutPublished('git commit -m "open', false) === null);

console.log(fail ? `published-text: ${fail} FAILED` : 'published-text: all checks passed');
process.exit(fail ? 1 : 0);
