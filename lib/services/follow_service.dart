import 'package:flutter/foundation.dart';
class FollowService {
  FollowService._private();
  static final FollowService instance = FollowService._private();

  /// Whether the map should follow the user's live location movements.
  final ValueNotifier<bool> isFollowing = ValueNotifier<bool>(false);

  /// Convenience to set value
  void setFollowing(bool v) => isFollowing.value = v;

  /// Toggle and return the new value
  bool toggle() {
    isFollowing.value = !isFollowing.value;
    return isFollowing.value;
  }
}
