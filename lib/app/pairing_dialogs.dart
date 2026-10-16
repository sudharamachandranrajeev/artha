import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr/qr.dart';

import '../core/security/crypto.dart' show CryptoException;
import '../core/sync/account_service.dart';
import '../core/sync/pairing.dart';
import '../ui/widgets.dart';
import 'providers.dart';
import 'sync_dialogs.dart';

/// How often each side looks at the pairing record, and how long a code
/// lasts (the server deletes it after 10 minutes; stop a little sooner).
const _poll = Duration(seconds: 2);
const _lifetime = Duration(minutes: 9, seconds: 50);

/// Acts on an `artha://` link that was scanned, pasted or opened.
Future<void> openArthaLink(BuildContext context, WidgetRef ref, String text) async {
  final ArthaLink link;
  try {
    link = ArthaLink.parse(text);
  } catch (e) {
    showError(context, e);
    return;
  }
  final session = await ref.read(sessionProvider).keys.session();
  if (!context.mounted) return;
  if (session != null) {
    showMessage(context, switch (link) {
      PairingLink() =>
        'This device already syncs as ${session['email']}. To add another device, scan '
            'the code with that device instead.',
      SetupLink() =>
        'This device already syncs as ${session['email']}. Sign out first to use another server.',
    });
    return;
  }
  switch (link) {
    case SetupLink():
      await showSyncDialog(context, mode: SyncMode.signUp, setup: link);
    case PairingLink():
      await showJoinDialog(context, link: link);
  }
}

/// A QR code, always dark on white with the quiet zone scanners need.
class QrCodeView extends StatelessWidget {
  QrCodeView(this.data, {super.key, this.size = 232})
    : _image = QrImage(QrCode(payload: QrPayload.fromString(data)));
  final String data;
  final QrImage _image;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'QR code to scan with the new device',
    child: CustomPaint(size: Size.square(size), painter: _QrPainter(_image)),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 4;
    final n = image.moduleCount;
    final cell = size.width / (n + 2 * quiet);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          // A hair of overlap so no seams show between modules.
          path.addRect(Rect.fromLTWH((x + quiet) * cell, (y + quiet) * cell, cell + 0.5, cell + 0.5));
        }
      }
    }
    canvas.drawPath(path, dark);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

/// On a signed-in device: shows a code another device can join with, and
/// asks before letting it in.
Future<void> showAddDevice(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _AddDeviceDialog());

enum _Offer { starting, showing, asked, sending, finishing, done, failed }

class _AddDeviceDialog extends ConsumerStatefulWidget {
  const _AddDeviceDialog();

  @override
  ConsumerState<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends ConsumerState<_AddDeviceDialog> {
  late final AccountService _account = ref.read(sessionProvider).account;
  _Offer _step = _Offer.starting;
  PairingLink? _link;
  JoinRequest? _request;
  String _code = '';
  String? _error;
  DateTime _deadline = DateTime.now();
  Timer? _timer;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    _offer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final link = _link;
    // Closing withdraws the code, unless the other device already has its keys.
    if (link != null && _step != _Offer.done) unawaited(_account.cancelPairing(link).catchError((_) {}));
    super.dispose();
  }

  Future<void> _offer() async {
    _timer?.cancel();
    final old = _link;
    _link = null;
    setState(() {
      _step = _Offer.starting;
      _error = null;
      _request = null;
    });
    try {
      if (old != null) await _account.cancelPairing(old);
      final link = await _account.offerPairing();
      if (!mounted) {
        await _account.cancelPairing(link);
        return;
      }
      _link = link;
      _deadline = DateTime.now().add(_lifetime);
      setState(() => _step = _Offer.showing);
      _timer = Timer.periodic(_poll, (_) => _look());
    } catch (e) {
      _fail(describeError(e));
    }
  }

  Future<void> _look() async {
    final link = _link;
    if (_looking || link == null) return;
    _looking = true;
    try {
      switch (_step) {
        case _Offer.showing:
          if (DateTime.now().isAfter(_deadline)) {
            _fail('This code expired. Make a new one.');
            return;
          }
          final request = await _account.pairingRequest(link);
          if (request != null && mounted && _step == _Offer.showing) {
            _code = await PairingCrypto.code(link, request.publicKey);
            setState(() {
              _request = request;
              _step = _Offer.asked;
            });
          }
        case _Offer.finishing:
          if (await _account.pairingFinished(link)) {
            _timer?.cancel();
            if (mounted) setState(() => _step = _Offer.done);
          }
        default:
      }
    } on CryptoException {
      _fail(
        'A device answered with something that does not match this code, so it was refused. '
        'Make a new code and try again.',
      );
    } on PairingClosed catch (e) {
      _fail(e.message);
    } catch (e) {
      // A dropped connection: keep trying until the code expires.
      if (_step != _Offer.showing && _step != _Offer.finishing) _fail(describeError(e));
    } finally {
      _looking = false;
      if (mounted && _step == _Offer.showing) setState(() {});
    }
  }

  void _fail(String message) {
    _timer?.cancel();
    final link = _link;
    _link = null;
    if (link != null) unawaited(_account.cancelPairing(link).catchError((_) {}));
    if (mounted) {
      setState(() {
        _step = _Offer.failed;
        _error = message;
      });
    }
  }

  Future<void> _approve() async {
    setState(() => _step = _Offer.sending);
    try {
      await _account.approvePairing(_link!, _request!);
      if (mounted) setState(() => _step = _Offer.finishing);
    } catch (e) {
      _fail(describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _request == null ? '' : _describe(_request!);
    final left = _deadline.difference(DateTime.now());
    return AlertDialog(
      title: Text(switch (_step) {
        _Offer.asked || _Offer.sending => 'Let this device in?',
        _Offer.done => 'Device added',
        _ => 'Add a device',
      }),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_step) {
              _Offer.starting => [const _Waiting('Making a code…')],
              _Offer.showing => [
                const Text(
                  'On a phone, point the camera app at this code. On a computer, open Artha, choose '
                  'Join from another device and paste the link.',
                ),
                const SizedBox(height: 16),
                Center(child: QrCodeView('$_link')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: '$_link'));
                        if (context.mounted) {
                          showMessage(context, 'Link copied. It works once, for 10 minutes.');
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy link'),
                    ),
                    const Spacer(),
                    Text(
                      'Expires in ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const StatusLabel(Status.info, 'You approve the device here before it gets anything.'),
              ],
              _Offer.asked || _Offer.sending => [
                Text('$name asks to join your sync account.'),
                const SizedBox(height: 16),
                _CodeBox(_code),
                const SizedBox(height: 16),
                const Text(
                  'Allow it only if the new device shows the same code. If it does not, deny: someone '
                  'else may have seen your code.',
                ),
              ],
              _Offer.finishing => [_Waiting('Waiting for $name to finish…')],
              _Offer.done => [StatusLabel(Status.good, '$name now syncs with this account.')],
              _Offer.failed => [StatusLabel(Status.critical, _error ?? 'Pairing stopped.')],
            },
          ),
        ),
      ),
      actions: switch (_step) {
        _Offer.asked => [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Deny')),
          FilledButton(onPressed: _approve, child: const Text('Allow')),
        ],
        _Offer.sending => [const FilledButton(onPressed: null, child: Text('Allow'))],
        _Offer.done => [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        _Offer.failed => [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: _offer, child: const Text('New code')),
        ],
        _ => [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      },
    );
  }
}

/// On a device that does not sync yet: joins an account through a link
/// from a device that does. Returns true when this device is signed in.
Future<bool> showJoinDialog(BuildContext context, {PairingLink? link}) async {
  final result = await showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _JoinDialog(link),
  );
  // A server's first-account link was pasted: hand over to account creation.
  if (result is SetupLink && context.mounted) {
    return showSyncDialog(context, mode: SyncMode.signUp, setup: result);
  }
  return result == true;
}

enum _Join { paste, asking, waiting, confirm, joining, failed }

class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog(this.link);
  final PairingLink? link;

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  late final AccountService _account = ref.read(sessionProvider).account;
  final _text = TextEditingController();
  _Join _step = _Join.paste;
  JoinTicket? _ticket;
  PairingGrant? _grant;
  String? _error;
  DateTime _deadline = DateTime.now();
  Timer? _timer;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    if (widget.link != null) _ask(widget.link!);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final ArthaLink link;
    try {
      link = ArthaLink.parse(_text.text);
    } catch (e) {
      setState(() => _error = describeError(e));
      return;
    }
    switch (link) {
      case PairingLink():
        await _ask(link);
      case SetupLink():
        Navigator.pop(context, link);
    }
  }

  Future<void> _ask(PairingLink link) async {
    setState(() {
      _step = _Join.asking;
      _error = null;
    });
    try {
      _ticket = await _account.requestJoin(link);
      _deadline = DateTime.now().add(_lifetime);
      if (!mounted) return;
      setState(() => _step = _Join.waiting);
      _timer = Timer.periodic(_poll, (_) => _look());
    } catch (e) {
      _fail(describeError(e));
    }
  }

  Future<void> _look() async {
    if (_looking || _step != _Join.waiting) return;
    _looking = true;
    try {
      if (DateTime.now().isAfter(_deadline)) {
        _fail('The code expired before the other device allowed this one. Make a new code there.');
        return;
      }
      final grant = await _account.joinGrant(_ticket!);
      if (grant != null && mounted) {
        _timer?.cancel();
        setState(() {
          _grant = grant;
          _step = _Join.confirm;
        });
      }
    } on PairingClosed catch (e) {
      _fail(e.message);
    } on CryptoException catch (e) {
      _fail(e.message);
    } catch (_) {
      // A dropped connection: keep trying until the code expires.
    } finally {
      _looking = false;
    }
  }

  Future<void> _join() async {
    setState(() => _step = _Join.joining);
    try {
      await _account.join(_ticket!, _grant!);
      await ref.read(syncProvider.notifier).run();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _fail(describeError(e));
    }
  }

  void _fail(String message) {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _step = _Join.failed;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grant = _grant;
    return AlertDialog(
      title: Text(_step == _Join.confirm ? 'Join this account?' : 'Join from another device'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_step) {
              _Join.paste => [
                const Text(
                  'On a device that already syncs, open Settings, then Sync, then Add a device. '
                  'Copy its link and paste it here. On a phone, scanning the code with the camera '
                  'app opens Artha directly.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Link from the other device',
                    hintText: 'artha://pair?…',
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async {
                        final clip = await Clipboard.getData(Clipboard.kTextPlain);
                        if (clip?.text != null) _text.text = clip!.text!.trim();
                      },
                    ),
                  ),
                  onSubmitted: (_) => _paste(),
                ),
              ],
              _Join.asking => [const _Waiting('Contacting the server…')],
              _Join.waiting => [
                const Text('Check that the other device shows this code, then allow it there.'),
                const SizedBox(height: 16),
                _CodeBox(_ticket!.code),
                const SizedBox(height: 16),
                const _Waiting('Waiting for the other device…'),
              ],
              _Join.confirm => [
                Text('This device will sync with ${grant!.email} on ${_ticket!.link.server.host}.'),
                const SizedBox(height: 12),
                const StatusLabel(
                  Status.warning,
                  'Continue only if you started this on your own device. Entries made here will go to '
                  'that account.',
                ),
              ],
              _Join.joining => [const _Waiting('Signing in and fetching your data…')],
              _Join.failed => [StatusLabel(Status.critical, _error ?? 'Joining stopped.')],
            },
          ),
        ),
      ),
      actions: switch (_step) {
        _Join.paste => [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _paste, child: const Text('Next')),
        ],
        _Join.confirm => [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _join, child: const Text('Join')),
        ],
        _Join.joining => [const FilledButton(onPressed: null, child: Text('Join'))],
        _Join.failed => [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          FilledButton(
            onPressed: () => setState(() {
              _step = _Join.paste;
              _error = null;
              _text.clear();
            }),
            child: const Text('Paste a new link'),
          ),
        ],
        _ => [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))],
      },
    );
  }
}

String _describe(JoinRequest r) {
  final name = r.name.trim().isEmpty ? 'A device' : '“${r.name.trim()}”';
  final platform = switch (r.platform) {
    'android' => 'Android',
    'linux' => 'Linux',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'ios' => 'iOS',
    _ => '',
  };
  return platform.isEmpty ? name : '$name ($platform)';
}

class _CodeBox extends StatelessWidget {
  const _CodeBox(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Semantics(
        label: 'Code ${code.split('').join(' ')}',
        excludeSemantics: true,
        child: Text(
          code,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}
