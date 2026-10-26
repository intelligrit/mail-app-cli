package mail

import (
	"encoding/json"
	"os/exec"
	"runtime"
	"testing"
)

// Every external/native primitive is shadowed. These tests cannot touch Mail.
func TestNativeArchiveBatches(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("JXA requires macOS")
	}
	script := "(function() { let Application, delay = () => {}, resolveMailbox;\n" + jsNativeArchive + `
archiveProgress = () => {};
function scenario(kind) {
 let inboxIDs = ['1','2','999'], selected = ['old'], clicks = 0, restored = false, focus = false;
 const msg = id => ({id: () => Number(id), messageId: () => 'rfc-' + id});
 const acc = {id: () => 'a', name: () => 'Test'};
 const inbox = {name: () => 'INBOX', account: () => acc, messages: {id: () => inboxIDs, byId: id => msg(String(id))}};
 const allMail = {messages: {whose: q => {
   if (q._or && q._or.length < 2) throw Error('Whose clause "_or" array requires at least two elements.');
   return () => kind === 'lost' ? [] : ['1','2','999'].map(msg).filter(m =>
     (q._or || [q]).some(clause => clause.messageId === m.messageId() || clause.id === m.id()));
 }}};
 resolveMailbox = (_a, name) => name === 'INBOX' ? inbox : allMail;
 const rows = ['1','2','999'].map(id=>({ids:[id]})), table = {}, sidebar = {};
 let selectedRows = [];
 const viewer = {window:{id:()=>77}};
 Object.defineProperty(viewer,'selectedMailboxes',{set:()=>{}});
 Object.defineProperty(viewer,'selectedMessages',{
   get:()=>()=>selected.map(msg),
   set:m=>{if(kind==='selection-failed'&&m.id()===1)throw Error('Message row unavailable');const index=rows.findIndex(r=>r.ids[0]===String(m.id()));selectedRows=[rows[kind==='offset'?Math.min(index+1,2):index]];selected=selectedRows[0].ids;}
 });
 const context = {viewer, window:{}, check:()=>{if(focus)throw Error('Mail became active');}};
 archiveContext = () => { if(kind==='no-window')throw Error('Open a Mail window'); return context; };
 archiveToolbarButton = () => ({button:true});
 captureArchiveView = () => ({saved:true, ids:['old']});
 restoreArchiveView = () => {context.check();if(kind==='restore-failed')throw Error('View unavailable');restored=true;selected=['old'];};
 axFindID = (_w,id)=> id==='Mail.messageList'?table:sidebar;
 axList = (el,key)=>key==='AXRows'?rows:key==='AXSelectedRows'?selectedRows:[];
 axSame = (a,b)=>a===b;
 axValue = (el,key)=>key==='AXEnabled'?kind!=='disabled':null;
 axSelectRows = (_t,rs)=>{selectedRows=rs;selected=rs.flatMap(r=>r.ids);if(kind==='extra')selected.push('999');};
 axPress = () => {
   clicks++;
   if(kind!=='stuck')inboxIDs=inboxIDs.filter(id=>!selected.includes(id)||(kind==='partial'&&id==='2'));
   if(kind==='focus')focus=true;
 };
 const mail = {inbox:()=>({mailboxes:()=>[inbox]}),selection:()=> (kind==='changed'?['999']:selected).map(msg),
   activate:()=>{throw Error('Must not activate Mail');},MessageViewer:()=>{throw Error('Must reuse existing viewer');}};
 const pending=(kind==='single'?['1']:['1','2']).map(id=>({msg:msg(id),acc,result:{id,status:'ok'}}));
 nativeArchiveMessages(mail,pending);
 return {kind,clicks,restored,inboxIDs,results:pending.map(e=>e.result)};
}
return JSON.stringify(['success','single','offset','partial','selection-failed','stuck','lost','disabled','extra','changed','focus','restore-failed','no-window'].map(scenario));
})();`
	output, err := exec.Command("osascript", "-l", "JavaScript", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("JXA: %v: %s", err, output)
	}
	var cases []struct {
		Kind     string
		Clicks   int
		Restored bool
		InboxIDs []string
		Results  []GlobalResult
	}
	if err := json.Unmarshal(output, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Kind, func(t *testing.T) {
			clicks, ok := 1, 0
			switch c.Kind {
			case "success", "offset", "focus", "restore-failed":
				ok = 2
			case "single", "partial", "selection-failed":
				ok = 1
			case "disabled", "extra", "changed", "no-window":
				clicks = 0
			}
			if c.Clicks != clicks {
				t.Fatalf("Archive clicks %d, want %d: %+v", c.Clicks, clicks, c.Results)
			}
			actual := 0
			for _, r := range c.Results {
				if r.Status == "ok" {
					actual++
				}
				if (c.Kind == "focus" || c.Kind == "restore-failed") && r.Warning == "" {
					t.Error("missing restoration warning")
				}
			}
			if actual != ok {
				t.Errorf("successes %d, want %d: %+v", actual, ok, c.Results)
			}
			if c.Kind == "selection-failed" && c.Results[0].Error != "Error: Message row unavailable" {
				t.Errorf("lost the specific selection failure: %+v", c.Results)
			}
			if c.InboxIDs[len(c.InboxIDs)-1] != "999" {
				t.Error("unrequested message archived")
			}
			if c.Kind != "focus" && c.Kind != "restore-failed" && c.Kind != "no-window" && !c.Restored {
				t.Error("view not restored")
			}
		})
	}
}

func TestNativeArchiveLock(t *testing.T) {
	unlock, err := lockNativeArchive()
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	otherUnlock, err := lockNativeArchive()
	if err == nil {
		otherUnlock()
		t.Fatal("concurrent archive allowed")
	}
}

func TestNativeArchiveRestoresRecreatedConversationRows(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("JXA requires macOS")
	}
	script := "(function(){ let delay=()=>{};\n" + jsNativeArchive + `
let rows=[{ids:['10','11']},{ids:['20']}], selectedRows=[rows[0]], preview=true;
const table={},sidebar={},sideRow={},viewer={};
const msg=id=>({id:()=>id});
Object.defineProperty(viewer,'previewPaneIsVisible',{get:()=>()=>preview,set:value=>{preview=value;}});
viewer.selectedMessages=()=>selectedRows.flatMap(r=>r.ids).map(msg);
axFindID=(_w,id)=>id==='Mail.messageList'?table:sidebar;
axList=(el,key)=>el===sidebar?[sideRow]:key==='AXRows'?rows:selectedRows;
axValue=(_e,key)=>key==='AXSelected'?true:null; // AXIndex is not a native attribute.
axSame=(a,b)=>a===b;
axSelectSidebar=()=>{rows=[{ids:['10','11']},{ids:['20']}];selectedRows=[rows[1]];};
axSelectRows=(_t,rs)=>{selectedRows=rs;};
selectNativeMessages=()=>{throw Error('Should restore the conversation row without scripting individual messages');};
const context={viewer,window:{},check:()=>{}};
const mail={inbox:()=>({messages:{byId:id=>({mailbox:()=>({messages:{byId:msg}})})}})};
const state=captureArchiveView(context);
if(preview)throw Error('Preview was not disabled');
restoreArchiveView(mail,context,state);
return JSON.stringify({ids:selectedIDs(viewer),preview,indices:state.indices});})();`
	output, err := exec.Command("osascript", "-l", "JavaScript", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("JXA: %v: %s", err, output)
	}
	var result struct {
		IDs     []string
		Preview bool
		Indices []int
	}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatal(err)
	}
	if len(result.IDs) != 2 || result.IDs[0] != "10" || result.IDs[1] != "11" || !result.Preview || len(result.Indices) != 1 || result.Indices[0] != 0 {
		t.Fatalf("view was not restored: %+v", result)
	}
}

func TestNativeArchiveSelectsConversationChild(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("JXA requires macOS")
	}
	script := "(function(){ let delay = () => {};\n" + jsNativeArchive + `
function scenario(kind) {
 let selected=[], selectedRows=[], expanded=false, presses=0;
 const child=id=>({ids:[String(id)],children:[]});
 const title={role:'AXStaticText',value:'Re: Topic',children:[]};
 const triangle={role:'AXDisclosureTriangle'}, group={ids:['1','2','3'],children:[triangle,title]}, neighbor=child(99);
 const duplicate={ids:['77','78'],children:[title]};
 const children=[child(1),child(2),child(3)],rows=kind==='distant'?[duplicate,group,child(88),child(89),neighbor]:[neighbor,group];
 const table={};
 const viewer={};
 Object.defineProperty(viewer,'selectedMessages',{get:()=>()=>selected.map(id=>({id:()=>id})),set:()=>{const row=kind==='distant'?neighbor:group;selectedRows=[row];selected=row.ids;}});
 const ctx={viewer,window:{},check:()=>{}};
 axFindID=()=>table;
 axList=(el,key)=>key==='AXRows'?rows:key==='AXSelectedRows'?selectedRows:(el.children||[]);
 axSame=(a,b)=>a===b;
 axValue=(el,key)=>key==='AXRole'?el.role:key==='AXValue'?(el===triangle?(expanded?1:0):el.value):null;
 axSelectRows=(_t,rs)=>{selectedRows=rs;selected=rs.flatMap(r=>r.ids);};
 axPress=()=>{presses++;if(kind!=='stuck'){expanded=true;rows.splice(2,0,...children);}};
 let error='';try{selectNativeMessages({},ctx,[{msg:{subject:()=>'Topic'},result:{id:'2'}},{msg:{subject:()=>'Topic'},result:{id:'3'}}]);}catch(e){error=String(e)}
 return {kind,selected,presses,error};
}
return JSON.stringify(['success','distant','stuck'].map(scenario));})();`
	output, err := exec.Command("osascript", "-l", "JavaScript", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("JXA: %v: %s", err, output)
	}
	var cases []struct {
		Kind, Error string
		Selected    []string
		Presses     int
	}
	if err := json.Unmarshal(output, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		if c.Kind == "stuck" {
			if c.Error == "" {
				t.Error("accepted unrequested conversation members")
			}
		} else if c.Error != "" || len(c.Selected) != 2 || c.Selected[0] != "2" || c.Selected[1] != "3" || c.Presses != 1 {
			t.Errorf("incorrect conversation selection: %+v", c)
		}
	}
}
