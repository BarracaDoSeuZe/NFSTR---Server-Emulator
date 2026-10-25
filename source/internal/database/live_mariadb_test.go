package database

import (
	"os"
	"testing"
)

// Runs only when NFSRUN_TEST_MARIADB=host:port:user:password:db and
// NFSRUN_TEST_MARIADB_CLIENT=<path to mariadb client> are set.
func liveDB(t *testing.T) *DB {
	spec, client := os.Getenv("NFSRUN_TEST_MARIADB"), os.Getenv("NFSRUN_TEST_MARIADB_CLIENT")
	if spec == "" || client == "" {
		t.Skip("live MariaDB not configured")
	}
	var c Config
	var port int
	parts := splitN(spec, ':', 5)
	c.Host, c.User, c.Password, c.Name = parts[0], parts[2], parts[3], parts[4]
	for _, ch := range parts[1] {
		port = port*10 + int(ch-'0')
	}
	c.Port = port
	return &DB{cfg: c, client: client}
}

func splitN(s string, sep rune, n int) []string {
	out := []string{}
	cur := ""
	for _, ch := range s {
		if ch == sep && len(out) < n-1 {
			out = append(out, cur)
			cur = ""
			continue
		}
		cur += string(ch)
	}
	return append(out, cur)
}

func TestLiveMariaDBBasics(t *testing.T) {
	d := liveDB(t)
	if err := d.Ping(); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ { // idempotent
		if err := d.Migrate(); err != nil {
			t.Fatalf("migrate #%d: %v", i, err)
		}
	}
	per, err := d.GetOrCreateIdentity("eatest.EXAMPLE-CLIENT1.0@ea.com", "EXAMPLE-CLIENT1.0")
	if err != nil {
		t.Fatal(err)
	}
	payload := `9aece800`
	sha := token() // unique per run so the test can be repeated on the same database
	json := `[{"blazeId":1000001,"gameType":"run_single","fields":{"TIME":184077}}]`
	ok, err := d.SaveGameReport(per.ID, "run_single", sha, payload, json)
	if err != nil || !ok {
		t.Fatalf("first save ok=%v err=%v", ok, err)
	}
	ok, err = d.SaveGameReport(per.ID, "run_single", sha, payload, json)
	if err != nil || ok {
		t.Fatalf("dup save ok=%v err=%v", ok, err)
	}
	// event id above signed INT range, as the game sends (2573038515)
	if _, err := d.query("DELETE FROM leaderboards WHERE board_key='race_single' AND event_id=2573038515;"); err != nil {
		t.Fatal(err)
	}
	better, err := d.UpsertPersonalBest(per.ID, "race_single", 2573038515, 132232, `{"vehicleId":1450737518,"q":"it's"}`)
	if err != nil || !better {
		t.Fatalf("first best=%v err=%v", better, err)
	}
	better, _ = d.UpsertPersonalBest(per.ID, "race_single", 2573038515, 140000, `{"worse":true}`)
	if better {
		t.Fatal("slower time must not be better")
	}
	better, _ = d.UpsertPersonalBest(per.ID, "race_single", 2573038515, 130000, `{"faster":true}`)
	if !better {
		t.Fatal("faster time must be better")
	}
	rows, err := d.query("SELECT score, metadata_json FROM leaderboards WHERE board_key='race_single' AND event_id=2573038515;")
	if err != nil || len(rows) != 1 || rows[0] != "130000\t{\"faster\":true}" {
		t.Fatalf("rows=%q err=%v", rows, err)
	}
}

func TestLiveLoadBoardEntries(t *testing.T) {
	d := liveDB(t)
	if err := d.Migrate(); err != nil {
		t.Fatal(err)
	}
	per, err := d.GetOrCreateIdentity("eatest.EXAMPLE-CLIENT1.0@ea.com", "EXAMPLE-CLIENT1.0")
	if err != nil {
		t.Fatal(err)
	}
	other, err := d.GetOrCreateIdentity("eatest.OTHER-PC.0@ea.com", "OTHER-PC.0")
	if err != nil {
		t.Fatal(err)
	}
	d.query("DELETE FROM leaderboards WHERE event_id IN (3118382346,2573038515);")
	d.UpsertPersonalBest(per.ID, "race_single", 3118382346, 128198, `{"vehicleId":3884276172,"win":true,"fields":{"ATMP":1}}`)
	d.UpsertPersonalBest(other.ID, "race_single", 3118382346, 127000, `{"vehicleId":1,"win":false}`)
	d.UpsertPersonalBest(per.ID, "race_single", 2573038515, 132232, `{"vehicleId":1450737518}`)
	es, err := d.LoadBoardEntries([]string{"race_single", "run_single"}, []uint64{3118382346, 2573038515, 42})
	if err != nil {
		t.Fatal(err)
	}
	if len(es) != 3 {
		t.Fatalf("entries=%+v", es)
	}
	// ordered by board, event, score
	if es[0].EventID != 2573038515 || es[1].EventID != 3118382346 || es[1].PersonaID != other.ID || es[2].Score != 128198 ||
		es[2].BlazeID != per.BlazeID || es[2].MetadataJSON != `{"vehicleId":3884276172,"win":true,"fields":{"ATMP":1}}` {
		t.Fatalf("entries=%+v", es)
	}
}

// Regression: "unexpected persona row" for an account without email,
// because the trailing empty column (TAB) was trimmed away.
func TestLiveIdentityWithoutEmail(t *testing.T) {
	d := liveDB(t)
	name := "NoMail-" + token()[:8]
	a, err := d.GetOrCreateIdentity("", name)
	if err != nil {
		t.Fatal(err)
	}
	b, err := d.GetOrCreateIdentity("", name) // second lookup parses the row with empty email
	if err != nil || a.ID != b.ID || b.Email != "" {
		t.Fatalf("a=%+v b=%+v err=%v", a, b, err)
	}
}

func TestLiveAnyBoardNamesAndListPersonas(t *testing.T) {
	d := liveDB(t)
	a, err := d.GetOrCreateIdentity("eatest.Player1@ea.com", "Player1")
	if err != nil {
		t.Fatal(err)
	}
	b, err := d.GetOrCreateIdentity("eatest.Rival@ea.com", "Rival")
	if err != nil {
		t.Fatal(err)
	}
	d.query("DELETE FROM leaderboards WHERE event_id=4129689794;")
	d.UpsertPersonalBest(a.ID, "run_single", 4129689794, 872864, `{}`)
	d.UpsertPersonalBest(b.ID, "run_single", 4129689794, 800000, `{}`)
	es, err := d.LoadBoardEntries(nil, []uint64{4129689794})
	if err != nil || len(es) != 2 || es[0].PersonaName != "Rival" || es[1].PersonaName != "Player1" || es[1].MetadataJSON != "{}" {
		t.Fatalf("entries=%+v err=%v", es, err)
	}
	refs, err := d.ListPersonas(a.ID, 50)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, r := range refs {
		if r.ID == a.ID {
			t.Fatal("self must be excluded")
		}
		if r.Name == "Rival" && r.BlazeID == b.BlazeID {
			found = true
		}
	}
	if !found {
		t.Fatalf("Rival missing from %+v", refs)
	}
}

func TestLiveLockerAndResume(t *testing.T) {
	d := liveDB(t)
	if err := d.Migrate(); err != nil {
		t.Fatal(err)
	}
	per, err := d.GetOrCreateIdentity("eatest.Locker@ea.com", "LockerUser")
	if err != nil {
		t.Fatal(err)
	}
	if got, ok, err := d.PersonaBySessionKey(per.SessionKey); err != nil || !ok || got.ID != per.ID || got.Email != "eatest.Locker@ea.com" {
		t.Fatalf("resume got=%+v ok=%v err=%v", got, ok, err)
	}
	if _, ok, _ := d.PersonaBySessionKey("nope"); ok {
		t.Fatal("unknown key must not resolve")
	}
	attrs := `[{"name":"location","value":"ID_STAGE_LOCATION_YOSEMITEAPPROACH,ID_STAGE_STATE_CA"},{"name":"q","value":"it's"}]`
	c, err := d.CreateLockerContent(per.ID, "SNAPSHOTS", "NFSTheRun", "", attrs, "client", 0)
	if err != nil || c.ID == 0 || c.Status != 1 || len(c.UploadToken) != 32 || c.AttributesJSON != attrs || c.OwnerName != "LockerUser" {
		t.Fatalf("create %+v %v", c, err)
	}
	if list, total, _ := d.ListLockerContents("SNAPSHOTS", per.ID, true, 0, 50); total != 0 || len(list) != 0 {
		t.Fatal("pending must not be listed")
	}
	if err := d.SetLockerStatus(c.ID, 0, 1234); err != nil {
		t.Fatal(err)
	}
	list, total, err := d.ListLockerContents("SNAPSHOTS", per.ID, true, 0, 50)
	if err != nil || total < 1 || len(list) < 1 || list[0].ID != c.ID || list[0].Size != 1234 || list[0].SubNames != "client" {
		t.Fatalf("list %+v total=%d err=%v", list, total, err)
	}
	if err := d.DeleteLockerContents(per.ID, []uint64{c.ID}); err != nil {
		t.Fatal(err)
	}
	if _, ok, _ := d.GetLockerContent(c.ID); ok {
		t.Fatal("deleted content still there")
	}
}

func TestLiveSpeedwallOwnedCounts(t *testing.T) {
	d := liveDB(t)
	a, _ := d.GetOrCreateIdentity("eatest.OwnA@ea.com", "OwnA")
	b, _ := d.GetOrCreateIdentity("eatest.OwnB@ea.com", "OwnB")
	d.query("DELETE FROM leaderboards WHERE event_id IN (777001,777002);")
	d.UpsertPersonalBest(a.ID, "race_single", 777001, 1000, `{}`)
	d.UpsertPersonalBest(b.ID, "race_single", 777001, 2000, `{}`)
	d.UpsertPersonalBest(b.ID, "race_single", 777002, 3000, `{}`)
	oc, err := d.SpeedwallOwnedCounts()
	if err != nil {
		t.Fatal(err)
	}
	got := map[uint64]uint64{}
	for _, o := range oc {
		got[o.PersonaID] = o.Count
	}
	if got[a.ID] < 1 || got[b.ID] < 1 {
		t.Fatalf("counts=%v", got)
	}
}

// Second persona on one account (race server copies), friends table.
func TestLiveMariaDBPersonasAndFriends(t *testing.T) {
	d := liveDB(t)
	if err := d.Migrate(); err != nil {
		t.Fatal(err)
	}
	a, err := d.GetOrCreateIdentity("v27a@ea.com", "V27A")
	if err != nil {
		t.Fatal(err)
	}
	ds1, err := d.GetOrCreateIdentity("c4v27serv01@ea.com", "NFS-DS-71")
	if err != nil {
		t.Fatal(err)
	}
	ds2, err := d.GetOrCreateIdentity("c4v27serv01@ea.com", "NFS-DS-72")
	if err != nil {
		t.Fatalf("second persona on the same account: %v", err)
	}
	if ds2.AccountID != ds1.AccountID || ds2.BlazeID == ds1.BlazeID {
		t.Fatalf("ds1 %+v ds2 %+v", ds1, ds2)
	}
	b, err := d.GetOrCreateIdentity("v27b@ea.com", "V27B")
	if err != nil || b.BlazeID == ds2.BlazeID {
		t.Fatalf("after: %+v %v", b, err)
	}
	if err := d.LinkAllFriends(); err != nil {
		t.Fatal(err)
	}
	if err := d.LinkAllFriends(); err != nil { // idempotent
		t.Fatal(err)
	}
	fr, err := d.ListFriends(a.ID)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, f := range fr {
		if f.Name == "NFS-DS-71" || f.ID == a.ID {
			t.Fatalf("bad friend %+v", f)
		}
		if f.Name == "V27B" {
			found = true
		}
	}
	if !found {
		t.Fatalf("friends %+v", fr)
	}
}
