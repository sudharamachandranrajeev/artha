/// <reference path="../pb_data/types.d.ts" />

// Sign-ups need the invite code from the ARTHA_SIGNUP_CODE environment
// variable. Without it set, nobody can sign up (only a superuser can add
// accounts), so a fresh server is never open to the world by accident.
onRecordCreateRequest((e) => {
  if (e.hasSuperuserAuth()) {
    return e.next()
  }
  const expected = $os.getenv("ARTHA_SIGNUP_CODE")
  const given = String(e.requestInfo().body["invite"] || "")
  if (expected.length < 12 || !$security.equal(given, expected)) {
    throw new ForbiddenError("Sign-up needs a valid invite code.")
  }
  return e.next()
}, "users")

// The e-mail address salts the key derived from the password, so changing it
// would lock the account out of its own vault.
onRecordRequestEmailChangeRequest((e) => {
  throw new BadRequestError("The e-mail address of an Artha account cannot be changed.")
}, "users")
