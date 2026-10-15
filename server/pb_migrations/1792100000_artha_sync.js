/// <reference path="../pb_data/types.d.ts" />

// Artha sync schema. The server stores only ciphertext: wrapped keys in
// `vaults`, an append-only log of encrypted changes per device in `changes`.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const own = "owner = @request.auth.id"
  const createOwn = "@request.auth.id != '' && @request.body.owner = @request.auth.id"
  const owner = { type: "relation", name: "owner", required: true, maxSelect: 1, cascadeDelete: true, collectionId: users.id }
  const device = { type: "text", name: "device", required: true, min: 32, max: 32, pattern: "^[0-9a-f]{32}$" }

  app.save(new Collection({
    type: "base",
    name: "vaults",
    listRule: own,
    viewRule: own,
    createRule: createOwn,
    // Re-wrapping after a password change; ownership can never move.
    updateRule: own + " && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)",
    deleteRule: null,
    fields: [
      owner,
      { type: "text", name: "wrapped_password", required: true, max: 500 },
      { type: "text", name: "wrapped_recovery", required: true, max: 500 },
      { type: "number", name: "version", required: true, onlyInt: true, min: 1 },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_vaults_owner ON vaults (owner)"],
  }))

  app.save(new Collection({
    type: "base",
    name: "devices",
    listRule: own,
    viewRule: own,
    createRule: createOwn,
    updateRule: own + " && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)",
    deleteRule: own,
    fields: [
      owner,
      device,
      { type: "text", name: "name", max: 100 },
      { type: "text", name: "platform", max: 20 },
      { type: "autodate", name: "created", onCreate: true },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_devices_owner_device ON devices (owner, device)"],
  }))

  // Append-only: no update or delete rule, so only a superuser can change history.
  app.save(new Collection({
    type: "base",
    name: "changes",
    listRule: own,
    viewRule: own,
    createRule: createOwn,
    updateRule: null,
    deleteRule: null,
    fields: [
      owner,
      device,
      { type: "number", name: "seq", required: true, onlyInt: true, min: 1 },
      { type: "text", name: "payload", required: true, max: 2000000 },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_changes_slot ON changes (owner, device, seq)"],
  }))

  // Accounts: password sign-in only, no listing of other users.
  users.oauth2.enabled = false
  users.otp.enabled = false
  users.listRule = "id = @request.auth.id"
  users.viewRule = "id = @request.auth.id"
  // The server password is a key derived in the app, never the typed one, so
  // the reset mail carries a code for the app instead of a link to
  // PocketBase's web page (which would store the typed password).
  users.resetPasswordTemplate.subject = "Reset your {APP_NAME} password"
  users.resetPasswordTemplate.body = [
    "<p>Hello,</p>",
    "<p>To choose a new password, open Artha, choose <strong>Forgot password</strong> and paste this reset code:</p>",
    '<p><code style="word-break: break-all">{TOKEN}</code></p>',
    "<p>You will also need your recovery key. The code works once and expires in 30 minutes.</p>",
    "<p>If you did not ask for this, ignore this e-mail: your password has not changed.</p>",
  ].join("\n")
  app.save(users)

  const settings = app.settings()
  settings.meta.appName = "Artha Sync"
  settings.batch.enabled = false
  settings.rateLimits.enabled = true
  settings.rateLimits.rules = [
    { label: "*:auth", audience: "", duration: 60, maxRequests: 10 },
    { label: "users:create", audience: "", duration: 3600, maxRequests: 5 },
    { label: "changes:create", audience: "@auth", duration: 10, maxRequests: 100 },
    { label: "/api/", audience: "", duration: 10, maxRequests: 300 },
  ]
  app.save(settings)
}, (app) => {
  for (const name of ["changes", "devices", "vaults"]) {
    app.delete(app.findCollectionByNameOrId(name))
  }
})
