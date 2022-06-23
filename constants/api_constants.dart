class ApiConstants {
  static const String url =
      "https://ec2-52-56-119-91.eu-west-2.compute.amazonaws.com";
  static const String urlUpdate = '$url/update';
  static const String urlLeave = '$url/leave';
  static const Map<String, String> headers = <String, String>{
    'Content-Type': 'application/json; charset=UTF-8',
  };
}
