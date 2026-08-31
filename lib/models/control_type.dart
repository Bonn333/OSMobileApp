/// A control action understood by the OpenShock API and the SignalR hub.
///
/// The numeric values are the wire format that the hub's `ControlV2` method
/// expects, and they must match the API's `ControlType` enum exactly:
/// `Stop = 0, Shock = 1, Vibrate = 2, Sound = 3`.
///
/// These were previously loose `int` constants numbered from zero
/// (`shock = 0, vibrate = 1, sound = 2`), which shifted every action down by
/// one: the Sound button vibrated, the Vibrate button shocked, and the Shock
/// button sent Stop. Keep the values pinned to the API enum rather than to
/// declaration order.
enum ControlType {
  stop(0),
  shock(1),
  vibrate(2),
  sound(3);

  const ControlType(this.value);

  /// Value sent on the wire as the `Type` field.
  final int value;
}
