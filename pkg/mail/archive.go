package mail

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// Mail's native Archive command uses its viewer selection. Serialize CLI
// callers so two processes cannot replace each other's selection before pressing.
func lockNativeArchive() (func(), error) {
	dir, err := os.UserCacheDir()
	if err != nil {
		return nil, err
	}
	dir = filepath.Join(dir, "mail-app-cli")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(filepath.Join(dir, "archive.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("another native archive is in progress; retry when it finishes: %w", err)
	}
	return func() { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN); _ = f.Close() }, nil
}

// ArchiveMessagesWithPolicy also supports scoped CLI calls without silently
// ignoring --gmail. Scoped IDs must actually belong to the requested mailbox.
func (c *Client) ArchiveMessagesWithPolicy(account, mailbox string, ids []string, policy string) (*GlobalSummary, error) {
	return c.mutateMessagesGlobal(ids, "archive", "", policy, account, mailbox)
}

// jsNativeArchive uses Mail's native Archive action once per account. Native
// Accessibility calls avoid System Events' slow traversal and broken AX arrays.
const jsNativeArchive = `
function sameMessageIDs(actual, expected) {
    const a = actual.map(String).sort(), b = expected.map(String).sort();
    return a.length === b.length && a.every((id, i) => id === b[i]);
}
function isGmailAccount(acc) {
    try {
        const host = acc.serverName().toLowerCase();
        if (host) return /(^|\.)(gmail|googlemail)\.com$/.test(host);
    } catch (e) {}
    return !!resolveMailbox(acc, 'All Mail');
}
// JXA's console.log writes to stderr; it does not provide console.error.
function archiveProgress(text) { console.log('mail-app-progress: ' + text); }
function axGet(element, attribute) {
    const value = Ref();
    const status = $.AXUIElementCopyAttributeValue(element, $(attribute), value);
    if (status) throw new Error(attribute + ' unavailable (Accessibility ' + status + ')');
    return ObjC.castRefToObject(value[0]);
}
function axValue(element, attribute) {
    try { return ObjC.unwrap(axGet(element, attribute)); } catch (e) { return null; }
}
function axList(element, attribute) {
    const array = axGet(element, attribute), values = [];
    for (let i = 0; i < Number(array.count); i++) values.push(array.objectAtIndex(i));
    return values;
}
function axSet(element, attribute, value) {
    const status = $.AXUIElementSetAttributeValue(element, $(attribute), value);
    if (status) throw new Error('Could not set ' + attribute + ' (Accessibility ' + status + ')');
}
function axSelectRows(table, rows) {
    const array = $.NSMutableArray.array;
    rows.forEach(row => array.addObject(row));
    axSet(table, 'AXSelectedRows', array);
    delay(0.03);
}
function axSelectSidebar(row) { axSet(row, 'AXSelected', $(true)); }
function axPress(element) {
    const status = $.AXUIElementPerformAction(element, $('AXPress'));
    if (status) throw new Error('Could not press Mail control (Accessibility ' + status + ')');
}
function axSame(a, b) { return !!$.CFEqual(a, b); }
function axFind(element, predicate, depth) {
    if (predicate(element)) return element;
    if (!depth || ['AXTable','AXOutline','AXRow'].indexOf(axValue(element, 'AXRole')) >= 0) return null;
    let children;
    try { children = axList(element, 'AXChildren'); } catch (e) { return null; }
    for (const child of children) {
        const found = axFind(child, predicate, depth - 1);
        if (found) return found;
    }
    return null;
}
function axFindID(element, identifier) {
    const found = axFind(element, el => axValue(el, 'AXIdentifier') === identifier, 7);
    if (!found) throw new Error('Mail control unavailable: ' + identifier);
    return found;
}
function archiveContext(mail) {
    ObjC.import('Cocoa'); ObjC.import('ApplicationServices');
    const proc = Application('System Events').processes.byName('Mail');
    if (proc.frontmost()) throw new Error('Leave Mail open behind Emacs before archiving');
    const app = $.AXUIElementCreateApplication(proc.unixId());
    const windows = axList(app, 'AXWindows');
    const viewers = mail.messageViewers();
    let viewer, window;
    for (const candidate of viewers) {
        const match = windows.find(w => axValue(w, 'AXIdentifier') === 'Mail.messageViewer.window.' + candidate.id());
        if (match && (!window || axValue(match, 'AXMain'))) { viewer = candidate; window = match; }
    }
    if (!viewer) throw new Error('Open a Mail message-list window, then leave it behind Emacs');
    const windowID = viewer.window.id();
    return {viewer: viewer, window: window, check: function() {
        if (proc.frontmost()) throw new Error('Mail became active; stopped before the next Archive action');
        if (viewer.window.id() !== windowID) throw new Error('Mail viewer changed; nothing else archived');
    }};
}
function archiveToolbarButton(context) {
    // Resolve the localized label through the stable menu identifier.
    const proc = Application('System Events').processes.byName('Mail');
    let label = null;
    try {
        const item = proc.menuBars[0].menuBarItems.byName('Message').menus[0].menuItems.byName('Archive');
        if (item.attributes.byName('AXIdentifier').value() === 'Mail.menuBar.messageMenu.archive') label = item.name();
    } catch(e) {}
    if (!label) {
        for (const menu of proc.menuBars[0].menuBarItems()) {
            for (const item of menu.menus[0].menuItems()) {
                try { if (item.attributes.byName('AXIdentifier').value() === 'Mail.menuBar.messageMenu.archive') label = item.name(); } catch(e) {}
            }
        }
    }
    const button = axFind(context.window, el => axValue(el, 'AXRole') === 'AXButton' &&
        axValue(el, 'AXDescription') === label, 7);
    if (!button) throw new Error('Add Archive to Mail’s toolbar using View > Customize Toolbar');
    return button;
}
function selectedIDs(viewer) { return (viewer.selectedMessages() || []).map(m => String(m.id())); }
function selectNativeMessage(mail, context, msg, id) {
    const viewer = context.viewer, wanted = String(id);
    context.check();
    // Mail's scripting setter sometimes chooses an adjacent row. Use it as a
    // starting point only; native AX selection is verified against message IDs.
    viewer.selectedMessages = msg;
    delay(0.03);
    const table = axFindID(context.window, 'Mail.messageList');
    if (sameMessageIDs(selectedIDs(viewer), [wanted])) return axList(table, 'AXSelectedRows');
    const selected = axList(table, 'AXSelectedRows');
    if (selected.length !== 1) throw new Error('Mail could not locate the requested message row');
    const index = axList(table, 'AXRows').findIndex(row => axSame(row, selected[0]));
    if (index < 0) throw new Error('Mail selection is no longer in the message list');
    function tryRow(rowIndex) {
        const rows = axList(table, 'AXRows');
        if (rowIndex < 0 || rowIndex >= rows.length) return null;
        context.check();
        axSelectRows(table, [rows[rowIndex]]);
        const ids = selectedIDs(viewer);
        if (sameMessageIDs(ids, [wanted])) return [rows[rowIndex]];
        if (ids.indexOf(wanted) < 0) return null;
        // Never archive unrequested members of a collapsed conversation.
        let triangle = null;
        for (const child of axList(rows[rowIndex], 'AXChildren')) {
            triangle = axFind(child, el => axValue(el, 'AXRole') === 'AXDisclosureTriangle', 3);
            if (triangle) break;
        }
        if (!triangle) return null;
        if (!Number(axValue(triangle, 'AXValue'))) {
            const before = rows.length;
            axPress(triangle);
            for (let n = 0; n < 20 && axList(table, 'AXRows').length <= before; n++) delay(0.05);
            if (axList(table, 'AXRows').length <= before) throw new Error('Mail did not expand the requested conversation');
        }
        const expanded = axList(table, 'AXRows');
        for (let offset = 1; offset <= ids.length && rowIndex + offset < expanded.length; offset++) {
            context.check();
            axSelectRows(table, [expanded[rowIndex + offset]]);
            if (sameMessageIDs(selectedIDs(viewer), [wanted])) return [expanded[rowIndex + offset]];
        }
        return null;
    }
    for (const candidate of [index, index - 1, index + 1]) {
        const rows = tryRow(candidate);
        if (rows) return rows;
    }
    // A conversation is sorted by its newest message. Mail's scripting setter
    // can instead land near the date of an older member, well away from its row.
    // Use the subject only to find candidates; IDs still decide what is safe.
    function normalizeSubject(value) {
        return typeof value === 'string' ? value.replace(/^(\s*(re|fw|fwd)\s*:\s*)+/i, '').trim().toLowerCase() : '';
    }
    let subject = '';
    try { subject = normalizeSubject(msg.subject()); } catch(e) {}
    if (subject) {
        const candidates = axList(table, 'AXRows');
        for (const candidate of candidates) {
            let matches = false;
            for (const child of axList(candidate, 'AXChildren')) {
                if (axFind(child, el => axValue(el, 'AXRole') === 'AXStaticText' &&
                    normalizeSubject(axValue(el, 'AXValue')) === subject, 4)) { matches = true; break; }
            }
            if (!matches) continue;
            // Expanding a previous candidate can change later row positions.
            const position = axList(table, 'AXRows').findIndex(row => axSame(row, candidate));
            const rows = tryRow(position);
            if (rows) return rows;
        }
    }
    throw new Error('Mail could not select exactly message ' + wanted + '; this message was not archived');
}
function selectNativeMessages(mail, context, entries, onFailure) {
    const rows = [], selected = [];
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        try {
            rows.push(...selectNativeMessage(mail, context, entry.msg, entry.result.id));
            selected.push(entry);
        } catch(e) {
            if (!onFailure) throw e;
            // Focus/window changes stop the operation, even in partial mode.
            context.check();
            onFailure(entry, e);
        }
        if (entries.length > 10 && (i + 1) % 10 === 0) archiveProgress('Selected ' + (i + 1) + ' of ' + entries.length + ' messages');
    }
    context.check();
    const table = axFindID(context.window, 'Mail.messageList');
    axSelectRows(table, rows);
    if (!sameMessageIDs(selectedIDs(context.viewer), selected.map(e => e.result.id))) {
        throw new Error('Mail did not select exactly the requested batch; nothing in this batch archived');
    }
    return selected;
}
function captureArchiveView(context) {
    const sidebar = axFindID(context.window, 'MailboxesOutlineView');
    const sideRows = axList(sidebar, 'AXRows').filter(r => axValue(r, 'AXSelected'));
    if (sideRows.length !== 1) throw new Error('Select one mailbox in Mail before using background Archive');
    const viewer = context.viewer;
    const state = {sidebar: sideRows[0], preview: viewer.previewPaneIsVisible(),
        ids: selectedIDs(viewer), rows: axList(axFindID(context.window, 'Mail.messageList'), 'AXSelectedRows')};
    const rows = axList(axFindID(context.window, 'Mail.messageList'), 'AXRows');
    state.indices = state.rows.map(selected => rows.findIndex(row => axSame(row, selected)));
    viewer.previewPaneIsVisible = false;
    return state;
}
function restoreArchiveView(mail, context, state) {
    context.check();
    try {
        axSelectSidebar(state.sidebar);
        delay(0.2);
        const remaining = [];
        for (const id of state.ids) {
            try {
                const box = mail.inbox().messages.byId(Number(id)).mailbox();
                remaining.push({msg: box.messages.byId(Number(id)), result: {id: id}});
            } catch(e) {}
        }
        const table = axFindID(context.window, 'Mail.messageList');
        // Rows may have been recreated on mailbox switch; verify before using
        // the original preview pane so a different message is never marked read.
        for (let attempt = 0; attempt < 10; attempt++) {
            const rows = axList(table, 'AXRows');
            try { axSelectRows(table, state.indices.map(i => rows[i]).filter(Boolean)); } catch(e) {}
            if (sameMessageIDs(selectedIDs(context.viewer), remaining.map(e => e.result.id))) break;
            delay(0.05);
        }
        if (!sameMessageIDs(selectedIDs(context.viewer), remaining.map(e => e.result.id))) {
            selectNativeMessages(mail, context, remaining);
        }
    } catch(e) {
        // An empty selection is safer than opening an unrelated message.
        try { axSelectRows(axFindID(context.window, 'Mail.messageList'), []); } catch(ignore) {}
        throw e;
    } finally {
        context.viewer.previewPaneIsVisible = state.preview;
    }
}
function nativeArchiveMessages(mail, pending) {
    if (!pending.length) return;
    let context = null, state = null, button = null;
    const groups = {};
    for (const entry of pending) {
        entry.result.status = 'failed'; entry.result.error = 'Archive was not completed';
        const id = entry.acc.id();
        if (!groups[id]) groups[id] = {acc: entry.acc, entries: []};
        groups[id].entries.push(entry);
    }
    try {
        const inboxes = mail.inbox().mailboxes();
        for (const group of Object.values(groups)) {
            const entries = group.entries;
            try {
                const inboxRef = inboxes.find(b => b.account().id() === group.acc.id());
                const inbox = inboxRef && resolveMailbox(group.acc, inboxRef.name());
                const allMail = resolveMailbox(group.acc, 'All Mail');
                if (!inbox || !allMail) throw new Error('Gmail Inbox or All Mail unavailable');
                const inboxIDs = new Set(inbox.messages.id().map(String)), active = [];
                for (const entry of entries) {
                    if (inboxIDs.has(entry.result.id)) {
                        entry.rfcID = entry.msg.messageId();
                        if (!entry.rfcID) { entry.result.error = 'Message-ID unavailable; cannot verify archive'; continue; }
                        active.push(entry);
                    } else if (allMail.messages.whose({id: Number(entry.result.id)})().length) {
                        entry.result.status = 'ok'; delete entry.result.error;
                    } else { entry.result.error = 'Message is outside Inbox and All Mail; refusing to archive it'; }
                }
                if (!active.length) continue;
                if (!context) {
                    const candidate = archiveContext(mail);
                    const candidateButton = archiveToolbarButton(candidate);
                    const candidateState = captureArchiveView(candidate);
                    context = candidate; button = candidateButton; state = candidateState;
                }
                context.check();
                archiveProgress('Selecting ' + active.length + ' messages in ' + group.acc.name());
                context.viewer.selectedMailboxes = inbox;
                delay(0.1);
                const selectable = selectNativeMessages(mail, context, active, (entry, error) => {
                    entry.selectionFailed = true;
                    entry.result.error = String(error);
                    archiveProgress('Could not select message ' + entry.result.id + '; continuing with the remaining messages');
                });
                if (!selectable.length) continue;
                context.check();
                const ids = selectable.map(e => e.result.id);
                if (!axValue(button, 'AXEnabled') || !sameMessageIDs(selectedIDs(context.viewer), ids) ||
                    !sameMessageIDs((mail.selection() || []).map(m => m.id()), ids)) {
                    throw new Error('Mail selection changed or Archive is disabled; nothing in this batch archived');
                }
                archiveProgress('Archiving ' + selectable.length + ' messages in ' + group.acc.name());
                axPress(button);
                archiveProgress('Verifying ' + selectable.length + ' messages in ' + group.acc.name());
                let remaining;
                for (let attempt = 0; attempt < 50; attempt++) {
                    remaining = new Set(inbox.messages.id().map(String));
                    if (ids.every(id => !remaining.has(id))) break;
                    delay(0.1);
                }
                const clauses = selectable.map(e => ({messageId: e.rfcID}));
                // JXA requires at least two operands for an _or whose clause.
                const query = clauses.length === 1 ? clauses[0] : {_or: clauses};
                const archived = new Set(allMail.messages.whose(query)().map(m => m.messageId()));
                for (const entry of selectable) {
                    if (remaining.has(entry.result.id)) entry.result.error = 'Message is still in Inbox after Archive';
                    else if (!archived.has(entry.rfcID)) entry.result.error = 'Message left Inbox but was not verified in All Mail; check Mail before retrying';
                    else { entry.result.status = 'ok'; entry.archived = true; delete entry.result.error; }
                }
                const ok = entries.filter(e => e.result.status === 'ok').length;
                archiveProgress(group.acc.name() + ': ' + ok + ' archived, ' + (entries.length - ok) + ' failed');
            } catch(e) {
                for (const entry of entries) if (entry.result.status !== 'ok' && !entry.selectionFailed) entry.result.error = String(e);
            }
        }
    } catch(e) {
        for (const entry of pending) if (entry.result.status !== 'ok') entry.result.error = String(e);
    } finally {
        if (state) {
            // A message just removed from the original Inbox cannot remain
            // selected there. Keep the surviving original selection only.
            const removed = new Set(pending.filter(e => e.archived).map(e => e.result.id));
            state.ids = state.ids.filter(id => !removed.has(id));
            archiveProgress('Restoring Mail selection');
            try { restoreArchiveView(mail, context, state); }
            catch(e) {
                // The archive result remains true even if view restoration fails.
                for (const entry of pending) entry.result.warning = 'Could not restore Mail view: ' + String(e);
            }
        }
    }
}
`
