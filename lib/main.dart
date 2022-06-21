import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';

import 'package:http/http.dart';

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyHttpOverrides extends HttpOverrides{
  @override
  HttpClient createHttpClient(SecurityContext? context){
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port)=> true;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool wait = false;
  Position? _currentPosition;
  String _currentAddress = "";
  String myId = "";

  @override
  void initState() {
    super.initState();
    checkLocation();
  }

  void _makeRequest() {
    setState(() {
      wait = true;
    });
    postResponse();
  }

  Future<dynamic> postResponse() async {
    bool error = false;
    ByteData data = await rootBundle.load('assets/certificates/client1.pfx');
    SecurityContext context = SecurityContext.defaultContext;
    context.useCertificateChainBytes(data.buffer.asUint8List());
    context.usePrivateKeyBytes(data.buffer.asUint8List());

    Response response = await post(
      Uri.parse('https://ec2-52-56-119-91.eu-west-2.compute.amazonaws.com/update'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, dynamic>{
        // 'my_id': myId,
        'send_messages': <String, String>{} // tutaj będzie obiekt
      }),
    ).catchError((err) {
      print(err);
      error = true;
    });

    if (!error) {
      print(response.statusCode);
      print(response.body);
    }
    setState(() {
      wait = false;
    });

    return response;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Padding(
                padding: EdgeInsets.only(bottom: 10.0),
                child: Text("Moja lokalizacja:")),
            Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Text(_currentAddress,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18.0))),
            Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Text(
                    "${_currentPosition?.latitude}, ${_currentPosition?.longitude}")),
            Padding(
                padding: EdgeInsets.only(top: 20.0),
                child: Text(wait
                    ? 'waiting...'
                    : 'Proszę kliknąć przycisk w prawym dolnym rogu ekranu')),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _makeRequest,
        tooltip: 'Increment',
        child: const Icon(Icons.api_rounded),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void checkLocation() {
    Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            forceAndroidLocationManager: true)
        .then((Position position) {
      setState(() {
        _currentPosition = position;
        _getAddressFromLatLng(position);
      });
    }).catchError((e) {
      print(e);
    });
    Future.delayed(const Duration(seconds: 15), ()=> checkLocation());
  }

  _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      Placemark place = placemarks[0];

      setState(() {
        _currentAddress =
            "${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print(e);
    }
  }
}
