/// <reference path="../pb_data/types.d.ts" />

// A pairing record lives for 10 minutes from creation, whatever the client
// asks for. Stale ones are deleted every 10 minutes.
onRecordCreate((e) => {
  e.record.set("expires", new Date(Date.now() + 10 * 60 * 1000).toISOString())
  e.record.set("request", "")
  e.record.set("response", "")
  return e.next()
}, "pairings")

cronAdd("artha_pairings_cleanup", "*/10 * * * *", () => {
  for (const r of $app.findRecordsByFilter("pairings", "expires < @now", "", 500, 0)) {
    $app.delete(r)
  }
})
