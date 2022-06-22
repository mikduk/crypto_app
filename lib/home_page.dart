import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';

import 'package:http/http.dart';

import 'api/api_leave.dart';
import 'constants/api_constants.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool wait = false;
  Position? _currentPosition;
  String _currentAddress1 = "";
  String _currentAddress2 = "";
  String _currentAddress3 = "";
  String myId = "";

  bool? algorithmResult;

  @override
  void initState() {
    super.initState();
    checkLocation();
  }

  Future<void> _closeApp() async {
    if (myId != "") {
      await leaveResponse(myId).then((value) => exit(0));
    } else {
      exit(0);
    }
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

    /** body calculate */
    String body = "";
    if (myId == "") {
      body = jsonEncode(<String, dynamic>{
        'send_messages': <String, String>{}
      });
    } else {
      body = jsonEncode(<String, dynamic>{
        'my_id': myId,
        'send_messages': <String, String>{} // tutaj będzie obiekt
      });
    }

    Response response = await post(
      Uri.parse(ApiConstants.urlUpdate),
      headers: ApiConstants.headers,
      body: body,
    ).catchError((err) {
      print(err);
      error = true;
    });

    if (!error) {
      print(response.statusCode);
      print(response.body);
      if (response.statusCode == 200) {
        dynamic responseObj = jsonDecode(response.body);
        setState(() {
          myId = responseObj["your_id"];
        });
      }
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
        child: Stack(children: [
          SizedBox(
              width: double.infinity,
              child:
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Padding(
                    padding: const EdgeInsets.only(top: 10.0, right: 10.0),
                    child: FloatingActionButton(
                      backgroundColor: Colors.red.withOpacity(0.6),
                      onPressed: _closeApp,
                      tooltip: 'CLOSE APP',
                      child: const Icon(Icons.close),
                    )),
              ])),
          SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Padding(
                      padding: EdgeInsets.only(bottom: 10.0),
                      child: Text("Moja lokalizacja:")),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 5.0),
                      child: Text(_currentAddress1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18.0))),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text("ul. $_currentAddress2",
                          style: const TextStyle(fontSize: 24.0))),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(_currentAddress3,
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
                          : 'Proszę kliknąć przycisk w prawym dolnym rogu ekranu'))
                ],
              ))
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _makeRequest,
        tooltip: 'START',
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
    Future.delayed(const Duration(seconds: 15), () => checkLocation());
  }

  _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);

      Placemark place = placemarks[0];

      setState(() {
        _currentAddress1 = "${place.locality}, ${place.subLocality}";
        _currentAddress2 = "${place.street}";
        _currentAddress3 = "${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print(e);
    }
  }
}