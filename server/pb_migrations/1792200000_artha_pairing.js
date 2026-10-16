/// <reference path="../pb_data/types.d.ts" />

// Device pairing and nightly backups.
//
// A signed-in device opens a `pairings` record and shows its id with a
// one-time secret as a QR code. The new device, not signed in yet, writes
// its request into the record once; the old device answers once with the
// account keys sealed to the new device. Both are ciphertext the server
// cannot read. Records expire after 10 minutes (pairing.pb.js sets
// `expires` and deletes stale ones).
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const fields = ["owner", "expires", "request", "response"]
  const only = (field) => fields.filter((f) => f !== field).map((f) => `@request.body.${f}:isset = false`).join(" && ")
  const live = "expires > @now"

  app.save(new Collection({
    type: "base",
    name: "pairings",
    // Never listed: a record is found only by the id in its QR code.
    listRule: null,
    viewRule: live,
    createRule: "@request.auth.id != '' && @request.body.owner = @request.auth.id && " + only("owner"),
    updateRule: live + " && (" +
      // The new device's request, once.
      `(request = '' && @request.body.request:isset = true && @request.body.request != '' && ${only("request")})` +
      " || " +
      // The owner's answer, once, and only after a request.
      `(owner = @request.auth.id && request != '' && response = '' && @request.body.response:isset = true && @request.body.response != '' && ${only("response")})` +
      ")",
    deleteRule: "owner = @request.auth.id",
    fields: [
      { type: "relation", name: "owner", required: true, maxSelect: 1, cascadeDelete: true, collectionId: users.id },
      { type: "date", name: "expires" },
      { type: "text", name: "request", max: 2000 },
      { type: "text", name: "response", max: 4000 },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE INDEX idx_pairings_expires ON pairings (expires)"],
  }))

  const settings = app.settings()
  // Daily copies of pb_data (ciphertext, e-mail addresses and devices), seven kept.
  settings.backups.cron = "30 3 * * *"
  settings.backups.cronMaxKeep = 7
  for (const rule of [
    { label: "pairings:create", audience: "", duration: 60, maxRequests: 10 },
    { label: "pairings:update", audience: "", duration: 60, maxRequests: 20 },
  ]) {
    if (!settings.rateLimits.rules.some((r) => r.label === rule.label)) {
      settings.rateLimits.rules.push(rule)
    }
  }
  app.save(settings)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("pairings"))
  const settings = app.settings()
  settings.backups.cron = ""
  settings.rateLimits.rules = settings.rateLimits.rules.filter((r) => !r.label.startsWith("pairings:"))
  app.save(settings)
})
