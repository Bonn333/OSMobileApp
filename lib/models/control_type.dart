enum ControlType {
  stop(0),
  shock(1),
  vibrate(2),
  sound(3);

  const ControlType(this.value);

  final int value;
}
