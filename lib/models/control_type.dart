/// Control action sent as the `Type` field of the hub's `ControlV2` message.
///
/// Values must match the API's `ControlType` enum, not declaration order.
enum ControlType {
  stop(0),
  shock(1),
  vibrate(2),
  sound(3);

  const ControlType(this.value);

  final int value;
}
