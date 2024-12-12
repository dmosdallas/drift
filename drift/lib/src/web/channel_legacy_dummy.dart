import 'package:stream_channel/stream_channel.dart';

/// Extension to transform a raw `MessagePort` from web workers into a Dart
/// [StreamChannel].
extension PortToChannel on dynamic {
  /// Converts this port to a two-way communication channel, exposed as a
  /// [StreamChannel].
  ///
  /// This can be used to implement a remote database connection over service
  /// workers.
  ///
  /// The [explicitClose] parameter can be used to control whether a close
  /// message should be sent through the channel when it is closed. This will
  /// cause it to be closed on the other end as well. Note that this is not a
  /// reliable way of determining channel closures though, as there is no event
  /// for channels being closed due to a tab or worker being closed.
  /// Both "ends" of a JS channel calling [channel] on their part must use the
  /// value for [explicitClose].
  @Deprecated(
    'Please use MessagePorts from package:web instead of those from dart:html. '
    'This extension will be removed from drift once `dart:html` is removed '
    'from the SDK.',
  )
  StreamChannel<Object?> channel({bool explicitClose = false}) {
    throw 'If this import was resolved, dart:html is not available.';
  }
}
