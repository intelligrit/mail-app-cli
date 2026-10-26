package mail

import (
	"os/exec"
	"runtime"
	"testing"
)

func TestResolveMoveMailbox(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("JXA requires macOS")
	}
	script := jsResolveMailbox + `
function account(id) { return {id: function() { return id; }}; }
function box(id, name) {
    return {account: function() { return account(id); }, name: function() { return name; }};
}
const first = box('a', 'Spam');
const second = box('b', 'Junk Email');
const mail = {junkMailbox: function() {
    return {mailboxes: function() { return [first, second]; }};
}};
function check(value, message) { if (!value) throw new Error(message); }
check(resolveMoveMailbox(mail, account('b'), '@junk') === second, 'wrong account');
check(resolveMoveMailbox(mail, account('a'), '@junk') === first, 'Spam not resolved');
check(resolveMoveMailbox(mail, account('missing'), '@junk') === null, 'must not use another account');
const literal = box('b', 'Junk');
const acc = {mailboxes: {
    name: function() { return ['Junk']; },
    at: function() { return literal; }
}};
check(resolveMoveMailbox(mail, acc, 'Junk') === literal, 'literal names must be preserved');
check(resolveMoveMailbox(mail, {mailboxes: {name: function() { return []; }}}, 'Missing') === null,
      'missing literal folder');
'passed';
`
	out, err := exec.Command("osascript", "-l", "JavaScript", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("resolver checks failed: %v: %s", err, out)
	}
}
