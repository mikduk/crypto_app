import 'package:geolocator/geolocator.dart';

class GeoMapping {
  static const _k = 1;
  static int map(Position position) {
    double long = position.longitude;
    double lat = position.latitude;
    int res = ((360/_k)*(lat+90)/_k+(long+180)/_k).ceil();
    return res;
  }
}