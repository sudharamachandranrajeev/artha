import 'package:pocketbase/pocketbase.dart';

import '../db/store.dart';
import '../security/crypto.dart';
import '../security/key_vault.dart';
import 'pairing.dart';
import 'pocketbase_remote.dart';
import 'sync_engine.dart';

/// Signed in, but the password no longer opens the vault (it was reset by
/// e-mail): the recovery key is needed once to re-wrap the data key.
class RecoveryKeyNeeded implements Exception {
  @override
  String toString() => 'Enter your recovery key to unlock your synced data';
}

/// The pairing record is gone: it expired, was used, or was cancelled.
class PairingClosed extends SyncException {
  PairingClosed(super.message);
}

/// Sync account lifecycle. The password never leaves this class: the server
/// gets a derived login secret, and the data key is only stored wrapped.
class AccountService {
  AccountService(this.vault, {required this.deviceId, this.deviceName = '', this.platform = ''});

  final KeyVault vault;
  final String deviceId;
  final String deviceName;
  final String platform;

  PocketBase? _pb;
  PasswordKeys? _pendingKeys;
  String? _pendingEmail;

  static const _password = 'password', _recovery = 'recovery';

  RecordService _users(PocketBase pb) => pb.collection('users');
  RecordService _vaults(PocketBase pb) => pb.collection('vaults');
  RecordService _pairings(PocketBase pb) => pb.collection('pairings');

  /// Creates the account and its vault. Returns the recovery key, which the
  /// user must write down: it is shown once and never stored.
  ///
  /// Repeating a sign-up that stopped before its vault was created finishes it.
  Future<String> signUp({
    required String server,
    required String email,
    required String password,
    required String invite,
  }) async {
    final url = validateServerUrl(server);
    final keys = await VaultCrypto.fromPassword(email, password);
    final mail = email.trim().toLowerCase();
    final pb = PocketBase(url.toString());
    try {
      await _users(pb).create(
        body: {
          'email': mail,
          'password': keys.authSecret,
          'passwordConfirm': keys.authSecret,
          'invite': invite,
        },
      );
    } on ClientException catch (e) {
      if (!isNotUnique(e)) await pbCall(() => Future<void>.error(e));
    }
    final ownerId = (await pbCall(() => _users(pb).authWithPassword(mail, keys.authSecret))).record.id;
    if (await _findVault(pb, ownerId) != null) {
      throw SyncException('This e-mail already has an account: sign in instead');
    }
    final dek = VaultCrypto.newDataKey();
    final recovery = VaultCrypto.newRecoveryKey();
    final body = {
      'owner': ownerId,
      'wrapped_password': await VaultCrypto.wrapKey(dek, keys.kek, _password),
      'wrapped_recovery': await VaultCrypto.wrapKey(dek, await VaultCrypto.recoveryKek(recovery), _recovery),
      'version': 1,
    };
    await pbCall(() => _vaults(pb).create(body: body));
    await _finish(pb, mail, keys.authSecret, ownerId, dek);
    return recovery;
  }

  /// Signs in on this device. Throws [RecoveryKeyNeeded] when the vault was
  /// wrapped under an older password; then call [unlockWithRecoveryKey].
  Future<void> signIn({required String server, required String email, required String password}) async {
    final url = validateServerUrl(server);
    final keys = await VaultCrypto.fromPassword(email, password);
    final mail = email.trim().toLowerCase();
    final pb = PocketBase(url.toString());
    final ownerId = (await pbCall(() => _users(pb).authWithPassword(mail, keys.authSecret))).record.id;
    final v = await _findVault(pb, ownerId);
    if (v == null) throw SyncException('Account setup did not finish: sign up again with the same details');
    final List<int> dek;
    try {
      dek = await VaultCrypto.unwrapKey(v.getStringValue('wrapped_password'), keys.kek, _password);
    } on CryptoException {
      _pb = pb;
      _pendingKeys = keys;
      _pendingEmail = mail;
      throw RecoveryKeyNeeded();
    }
    await _finish(pb, mail, keys.authSecret, ownerId, dek);
  }

  /// After [RecoveryKeyNeeded]: opens the vault with the recovery key and
  /// re-wraps the data key under the current password.
  Future<void> unlockWithRecoveryKey(String recoveryKey) async {
    final pb = _pb, keys = _pendingKeys, mail = _pendingEmail;
    if (pb == null || keys == null || mail == null) throw SyncException('Sign in first');
    final ownerId = pb.authStore.record!.id;
    final v = (await _findVault(pb, ownerId))!;
    final dek = await VaultCrypto.unwrapKey(
      v.getStringValue('wrapped_recovery'),
      await VaultCrypto.recoveryKek(recoveryKey),
      _recovery,
    );
    final wrapped = await VaultCrypto.wrapKey(dek, keys.kek, _password);
    await pbCall(() => _vaults(pb).update(v.id, body: {'wrapped_password': wrapped}));
    await _finish(pb, mail, keys.authSecret, ownerId, dek);
  }

  /// Sends the server's password-reset e-mail (needs SMTP on the server).
  Future<void> requestPasswordReset({required String server, required String email}) {
    final pb = PocketBase(validateServerUrl(server).toString());
    return pbCall(() => _users(pb).requestPasswordReset(email.trim().toLowerCase()));
  }

  /// Sets a new password from the e-mailed token; the recovery key then
  /// re-opens the vault.
  Future<void> resetPassword({
    required String server,
    required String email,
    required String token,
    required String newPassword,
    required String recoveryKey,
  }) async {
    final url = validateServerUrl(server);
    // Reject a mistyped recovery key before anything changes on the server.
    await VaultCrypto.recoveryKek(recoveryKey);
    final keys = await VaultCrypto.fromPassword(email, newPassword);
    final pb = PocketBase(url.toString());
    await pbCall(() => _users(pb).confirmPasswordReset(token.trim(), keys.authSecret, keys.authSecret));
    try {
      await signIn(server: server, email: email, password: newPassword);
    } on RecoveryKeyNeeded {
      await unlockWithRecoveryKey(recoveryKey);
    }
  }

  /// Changes the password and re-wraps the data key. If this stops half way,
  /// signing in with the new password asks for the recovery key once.
  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    final s = await vault.session();
    final dek = await vault.dataKey();
    if (s == null || dek == null) throw SyncException('Not signed in');
    final mail = s['email']! as String, ownerId = s['userId']! as String;
    final oldKeys = await VaultCrypto.fromPassword(mail, oldPassword);
    final newKeys = await VaultCrypto.fromPassword(mail, newPassword);
    final pb = await _signedIn();
    final v = (await _findVault(pb, ownerId))!;
    // Checked here too so a wrong old password fails before any change.
    await VaultCrypto.unwrapKey(v.getStringValue('wrapped_password'), oldKeys.kek, _password);
    final wrapped = await VaultCrypto.wrapKey(dek, newKeys.kek, _password);
    await pbCall(
      () => _users(pb).update(
        ownerId,
        body: {
          'oldPassword': oldKeys.authSecret,
          'password': newKeys.authSecret,
          'passwordConfirm': newKeys.authSecret,
        },
      ),
    );
    await vault.setSession({...s, 'secret': newKeys.authSecret});
    await pbCall(() => _users(pb).authWithPassword(mail, newKeys.authSecret));
    await pbCall(() => _vaults(pb).update(v.id, body: {'wrapped_password': wrapped}));
  }

  // Pairing (see [PairingCrypto]). On the signed-in device: [offerPairing],
  // then poll [pairingRequest], then [approvePairing] or [cancelPairing].
  // On the new device: [requestJoin], poll [joinGrant], then [join].

  /// Opens a pairing record and returns the link to show as a QR code.
  Future<PairingLink> offerPairing() async {
    final pb = await _signedIn();
    final ownerId = (await vault.session())!['userId']! as String;
    final r = await pbCall(() => _pairings(pb).create(body: {'owner': ownerId}));
    return PairingLink(Uri.parse(pb.baseURL), r.id, VaultCrypto.randomBytes(32));
  }

  /// The request waiting on [link], or null while there is none.
  Future<JoinRequest?> pairingRequest(PairingLink link) async {
    final r = await _pairing(await _signedIn(), link.id, 'This code has expired. Make a new one.');
    final sealed = r.getStringValue('request');
    return sealed.isEmpty ? null : PairingCrypto.openRequest(link, sealed);
  }

  /// Sends this account's keys to the device that made [request].
  Future<void> approvePairing(PairingLink link, JoinRequest request) async {
    final s = await vault.session();
    final dek = await vault.dataKey();
    if (s == null || dek == null) throw SyncException('Not signed in');
    final grant = PairingGrant(
      email: s['email']! as String,
      userId: s['userId']! as String,
      secret: s['secret']! as String,
      dataKey: dek,
    );
    final response = await PairingCrypto.sealGrant(link, request.publicKey, grant);
    final pb = await _signedIn();
    await pbCall(() => _pairings(pb).update(link.id, body: {'response': response}));
  }

  /// Whether the new device has finished with [link] (it deletes the record).
  Future<bool> pairingFinished(PairingLink link) async {
    try {
      await _pairing(await _signedIn(), link.id, '');
      return false;
    } on PairingClosed {
      return true;
    }
  }

  /// Withdraws [link]; a device waiting on it is told it was declined.
  Future<void> cancelPairing(PairingLink link) async {
    try {
      await (await _signedIn()).collection('pairings').delete(link.id);
    } on ClientException catch (e) {
      if (e.statusCode != 404) await pbCall(() => Future<void>.error(e));
    }
  }

  /// On a new device: asks to join through [link]. The ticket's code must
  /// match the one the other device shows.
  Future<JoinTicket> requestJoin(PairingLink link) async {
    if (await vault.session() != null) throw SyncException('This device already syncs. Sign out first.');
    final keyPair = await PairingCrypto.newKeyPair();
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final sealed = await PairingCrypto.sealRequest(
      link,
      JoinRequest(name: deviceName, platform: platform, publicKey: publicKey),
    );
    final pb = PocketBase(link.server.toString());
    try {
      await _pairings(pb).update(link.id, body: {'request': sealed});
    } on ClientException catch (e) {
      // Rules hide a used or expired record, so both read as not found.
      if (e.statusCode == 404) {
        throw PairingClosed(
          'This code has expired or was already used. Make a new one on your other device.',
        );
      }
      await pbCall(() => Future<void>.error(e));
    }
    return JoinTicket(link, keyPair, await PairingCrypto.code(link, publicKey));
  }

  /// The account the other device sent, once it approved; null while waiting.
  Future<PairingGrant?> joinGrant(JoinTicket ticket) async {
    final r = await _pairing(
      PocketBase(ticket.link.server.toString()),
      ticket.link.id,
      'The other device declined, or the code expired.',
    );
    final sealed = r.getStringValue('response');
    return sealed.isEmpty ? null : PairingCrypto.openGrant(ticket, sealed);
  }

  /// Signs this device in with [grant] and closes the pairing.
  Future<void> join(JoinTicket ticket, PairingGrant grant) async {
    final pb = PocketBase(ticket.link.server.toString());
    final ownerId = (await pbCall(() => _users(pb).authWithPassword(grant.email, grant.secret))).record.id;
    if (ownerId != grant.userId || await _findVault(pb, ownerId) == null) {
      throw SyncException('The other device sent keys for an account this server does not know');
    }
    await _finish(pb, grant.email, grant.secret, ownerId, grant.dataKey);
    try {
      await _pairings(pb).delete(ticket.link.id);
    } on ClientException {
      // It expires on its own.
    }
  }

  Future<RecordModel> _pairing(PocketBase pb, String id, String gone) async {
    try {
      return await _pairings(pb).getOne(id);
    } on ClientException catch (e) {
      if (e.statusCode == 404) throw PairingClosed(gone);
      return pbCall(() => Future<RecordModel>.error(e));
    }
  }

  /// A sync engine for the signed-in account, or null when signed out. Ask
  /// for one per sync run: it signs in again when the server token expired.
  Future<SyncEngine?> engine(Store store) async {
    final s = await vault.session();
    final dek = await vault.dataKey();
    if (s == null || dek == null) return null;
    final pb = await _signedIn();
    final ownerId = s['userId']! as String;
    return SyncEngine(store, PocketBaseRemote(pb, ownerId), dek, ownerId);
  }

  Future<void> signOut() async {
    _pb?.authStore.clear();
    _pb = null;
    await vault.signOut();
  }

  Future<PocketBase> _signedIn() async {
    final s = await vault.session();
    if (s == null) throw SyncException('Not signed in');
    final pb = _pb ??= PocketBase(s['server']! as String);
    if (!pb.authStore.isValid) {
      await pbCall(() => _users(pb).authWithPassword(s['email']! as String, s['secret']! as String));
    }
    return pb;
  }

  Future<RecordModel?> _findVault(PocketBase pb, String ownerId) async {
    final r = await pbCall(
      () =>
          _vaults(pb).getList(perPage: 1, skipTotal: true, filter: pb.filter('owner = {:o}', {'o': ownerId})),
    );
    return r.items.firstOrNull;
  }

  /// Keeps the keys on this device and registers it with the account.
  Future<void> _finish(PocketBase pb, String mail, String secret, String ownerId, List<int> dek) async {
    try {
      await pb
          .collection('devices')
          .create(body: {'owner': ownerId, 'device': deviceId, 'name': deviceName, 'platform': platform});
    } on ClientException catch (e) {
      if (!isNotUnique(e)) await pbCall(() => Future<void>.error(e));
    }
    await vault.setDataKey(dek);
    await vault.setSession({'server': pb.baseURL, 'email': mail, 'userId': ownerId, 'secret': secret});
    _pb = pb;
    _pendingKeys = null;
    _pendingEmail = null;
  }
}
