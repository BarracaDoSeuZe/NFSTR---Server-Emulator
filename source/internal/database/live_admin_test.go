package database

import (
	"strings"
	"testing"
	"time"
)

func TestLiveLockerRatings(t *testing.T) {
	d := liveDB(t)
	if err := d.Migrate(); err != nil {
		t.Fatal(err)
	}
	sfx := token()[:6]
	a, _ := d.GetOrCreateIdentity("rate-a"+sfx+"@ea.com", "RA"+sfx)
	b, _ := d.GetOrCreateIdentity("rate-b"+sfx+"@ea.com", "RB"+sfx)
	c, err := d.CreateLockerContent(a.ID, "SNAPSHOTS", "NFSTheRun", "", "{}", "client", 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range []struct {
		p    uint64
		rate int64
	}{{b.ID, 1}, {b.ID, 1}, {a.ID, 1}} {
		if err := d.RateLockerContent(c.ID, r.p, r.rate); err != nil {
			t.Fatal(err)
		}
	}
	d.IncrementLockerUseCount(c.ID)
	d.IncrementLockerUseCount(c.ID)
	got, ok, err := d.GetLockerContent(c.ID)
	if err != nil || !ok || got.RatingCount != 2 || got.RatingSum != 2 || got.UseCount != 2 {
		t.Fatalf("content %+v ok=%v err=%v", got, ok, err)
	}
	mine, err := d.LockerMyRatings(b.ID, []uint64{c.ID, 999999999})
	if err != nil || mine[c.ID] != 1 || len(mine) != 1 {
		t.Fatalf("mine %v %v", mine, err)
	}
}

func TestLiveAdminResetReserveRenameDelete(t *testing.T) {
	d := liveDB(t)
	if err := d.Migrate(); err != nil {
		t.Fatal(err)
	}
	sfx := token()[:6]
	name := "Adm" + sfx
	key1, key2 := token()[:32]+token()[:32], token()[:32]+token()[:32]
	if _, _, err := d.AuthenticateLauncherPublicKey("eatest."+name+"@ea.com", name, key1, "", "open", time.Hour); err != nil {
		t.Fatal(err)
	}
	pi, ok, err := d.FindPersona(strings.ToLower(name)) // case-insensitive
	if err != nil || !ok || !pi.Bound || pi.Name != name {
		t.Fatalf("find %+v %v %v", pi, ok, err)
	}
	// lost key: reset + code; the name waits for the code even in open mode
	if err := d.ResetLauncherDevice(name); err != nil {
		t.Fatal(err)
	}
	code, _, err := d.CreateLauncherClaim(name, 12*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if r, _ := d.LauncherNameReserved(name); !r {
		t.Fatal("name not reserved")
	}
	if _, _, err := d.AuthenticateLauncherPublicKey("eatest."+name+"@ea.com", name, key2, "", "open", time.Hour); err == nil || !strings.Contains(err.Error(), "INVITE_CODE") {
		t.Fatalf("no code accepted: %v", err)
	}
	if _, _, err := d.AuthenticateLauncherPublicKey("eatest."+name+"@ea.com", name, key2, "AAAA-BBBB-CCCC", "open", time.Hour); err == nil {
		t.Fatal("wrong code accepted")
	}
	per, _, err := d.AuthenticateLauncherPublicKey("eatest."+name+"@ea.com", name, key2, code, "open", time.Hour)
	if err != nil || per.ID != pi.ID || per.BlazeID != pi.BlazeID {
		t.Fatalf("recover %+v %v (want persona %d)", per, err, pi.ID)
	}
	if r, _ := d.LauncherNameReserved(name); r {
		t.Fatal("code still pending after use")
	}
	if cl, _ := d.ListLauncherClaims(); len(cl) > 0 {
		for _, c := range cl {
			if c.Name == name {
				t.Fatal("used code listed")
			}
		}
	}
	// codes cancel
	other := "Can" + sfx
	if _, _, err := d.CreateLauncherClaim(other, time.Hour); err != nil {
		t.Fatal(err)
	}
	if found, err := d.CancelLauncherClaim(other); err != nil || !found {
		t.Fatalf("cancel %v %v", found, err)
	}
	if found, _ := d.CancelLauncherClaim(other); found {
		t.Fatal("cancelled twice")
	}
	// rename: the key follows the persona
	newName := "Ren" + sfx
	if _, err := d.RenamePersona(name, newName); err != nil {
		t.Fatal(err)
	}
	per, _, err = d.AuthenticateLauncherPublicKey("eatest."+name+"@ea.com", name, key2, "", "open", time.Hour)
	if err != nil || per.Name != newName {
		t.Fatalf("after rename %+v %v", per, err)
	}
	// a lost key after the rename: reset + code with the new PERSONA
	d.ResetLauncherDevice(newName)
	code2, _, _ := d.CreateLauncherClaim(newName, time.Hour)
	key3 := token()[:32] + token()[:32]
	if p3, _, err := d.AuthenticateLauncherPublicKey("eatest."+newName+"@ea.com", newName, key3, code2, "open", time.Hour); err != nil || p3.ID != per.ID {
		t.Fatalf("recover after rename %+v %v", p3, err)
	}
	key2 = key3
	taken := "Tkn" + sfx
	d.GetOrCreateIdentity("eatest."+taken+"@ea.com", taken)
	if _, err := d.RenamePersona(newName, taken); err == nil {
		t.Fatal("rename onto a used name")
	}
	// delete: everything goes, the account too
	c, _ := d.CreateLockerContent(per.ID, "SNAPSHOTS", "x", "", "{}", "client", 0)
	d.RateLockerContent(c.ID, per.ID, 1)
	del, photos, err := d.DeletePersona(newName)
	if err != nil || del.ID != per.ID || len(photos) != 1 || photos[0] != c.ID {
		t.Fatalf("delete %+v %v %v", del, photos, err)
	}
	if _, ok, _ := d.FindPersona(newName); ok {
		t.Fatal("persona still there")
	}
	if rows, _ := d.query("SELECT COUNT(*) FROM accounts WHERE id=" + itoaU(del.AccountID) + ";"); len(rows) == 0 || strings.TrimSpace(rows[0]) != "0" {
		t.Fatalf("account kept: %v", rows)
	}
	if _, ok, _ := d.GetLockerContent(c.ID); ok {
		t.Fatal("photo kept")
	}
	if ok, _ := d.LauncherPublicKeyKnown(key2); ok {
		t.Fatal("key kept")
	}
	if _, _, err := d.DeletePersona(newName); err == nil {
		t.Fatal("deleted twice")
	}
	list, err := d.ListPersonaInfo(1000)
	if err != nil || len(list) == 0 {
		t.Fatalf("list %v %v", len(list), err)
	}
}

func itoaU(v uint64) string {
	b := []byte{}
	for {
		b = append([]byte{byte('0' + v%10)}, b...)
		v /= 10
		if v == 0 {
			return string(b)
		}
	}
}
