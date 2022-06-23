import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart';

import '../constants/api_constants.dart';
import 'geo_mapping.dart';

/// p
final BigInt N = BigInt.parse('825181417503968752428899161001');
final BigInt H = BigInt.from(2);

enum ProtocolStateStatus { init, startSent, startResponseSent, part2Sent }

enum AlgorithmSteps { start, startResponse, part2, finish, terminate }

class ProtocolState {
  // fields
  String otherClientId = "";
  String myClientId = "";
  late BigInt x;

  /// randomFromZp
  late final BigInt a1;
  late final BigInt a2;
  late final BigInt a3;

  late BigInt sharedM;
  late BigInt sharedL;
  late BigInt otherPartyP;
  late BigInt otherPartyQ;

  late BigInt P;
  late BigInt Q;
  late BigInt R;

  ProtocolStateStatus state = ProtocolStateStatus.init;

  void Function(bool?) resultToInterface = (bool? res) {};

  late String requestBody;
  List requestData = [];

  // constructor
  ProtocolState(String otherClientID, String myClientID, Position position,
      bool? Function(bool?) setMyState) {
    otherClientId = otherClientID;
    myClientId = myClientID;
    x = BigInt.from(GeoMapping.map(position));
    resultToInterface = setMyState;
    a1 = randomFromZp();
    a2 = randomFromZp();
    a3 = randomFromZp();
    requestBody = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, String>{} // tutaj będzie obiekt
    });
  }

  void startAlgorithm() async {
    print('\x1B[34mAlgorithm:\x1B[0m');
    switch (state) {
      case ProtocolStateStatus.init:
        aliceSendStart();
        if (state == ProtocolStateStatus.init && requestData.length == 2) {
          bobReceiveStart(requestData[0], requestData[1]);
        }
        break;
      case ProtocolStateStatus.startSent:
        if (requestData.length == 4) {
          aliceReceiveStartResponse(requestData[0], requestData[1], requestData[2], requestData[3]);
        } else {
          print('\x1B[37mHi, I\'m waiting for Bob...\x1B[0m');
        }
        break;
      case ProtocolStateStatus.startResponseSent:
        if (requestData.length == 3) {
          bobReceivePart2(requestData[0], requestData[1], requestData[2]);
        } else {
          print('\x1B[37mHi, I\'m waiting for Alice...\x1B[0m');
        }
        break;
      case ProtocolStateStatus.part2Sent:
        break;
    }
    request(requestBody);
    Future.delayed(const Duration(seconds: 4), startAlgorithm);
  }

  Future<void> request(String body) async {
    bool error = false;
    ByteData data = await rootBundle.load('assets/certificates/client1.pfx');
    SecurityContext context = SecurityContext.defaultContext;
    context.useCertificateChainBytes(data.buffer.asUint8List());
    context.usePrivateKeyBytes(data.buffer.asUint8List());

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
        print('\x1B[37mTEST-PRINT:\x1B[0m');
        bool _hasData = false;
        String? _step;
        List? _value;
        try {
          _step = responseObj["inbox"][otherClientId]["algorithm_step"];
          _value = (responseObj["inbox"][otherClientId]["values"]);
          _hasData = true;
        } catch (e) {
          print("-");
        }
        if (_hasData) {
          requestData = _value!;
        }
      }
    }
  }

  // functions
  void aliceSendStart() {
    try {
      if (state != ProtocolStateStatus.init) {
        throw Exception("Invalid state");
      }

      /// zakładając że mamy tylko 2 użytkowników, zaczyna ten z większym id (Alice)
      if (myClientId == "" || otherClientId == "") {
        return;
      } else if (myClientId.compareTo(otherClientId) <= 0) {
        print('\x1B[37mHi, I\'m Bob!\x1B[0m');
        return;
      }

      print('\x1B[37mHi, I\'m Alicia!\x1B[0m');

      String body = jsonEncode(<String, dynamic>{
        'my_id': myClientId,
        'send_messages': <String, dynamic>{
          otherClientId: <String, dynamic>{
            'algorithm_step': AlgorithmSteps.start.name,
            'values': [
              H.modPow(a1, N).toString(),
              H.modPow(a2, N).toString(),
            ]
          }
        }
      });

      sendUpdate(body);
      state = ProtocolStateStatus.startSent;
    } catch (e) {
      String err = e.toString();
      print('\x1B[33m$err\x1B[0m');
    }
  }

  /// może tylko ten z mniejszym ID otrzymać (Bob)
  void bobReceiveStart(hA1, hA2) {
    try {
      if (state != ProtocolStateStatus.init) {
        print("I am further");
        throw Exception("Invalid state");
      }

      print("Bob official introduce");

      BigInt _hA1 = BigInt.parse(hA1);
      BigInt _hA2 = BigInt.parse(hA2);

      if (_hA1 == BigInt.one || _hA2 == BigInt.one) {
        return sendTerminate();
      }

      BigInt m = _hA1.modPow(a1, N);
      BigInt l = _hA2.modPow(a2, N);
      P = l.modPow(a3, N);
      Q = H.modPow(a3, N) * m.modPow(x, N);

      sharedM = m;
      sharedL = l;

      String body = jsonEncode(<String, dynamic>{
        'my_id': myClientId,
        'send_messages': <String, dynamic>{
          otherClientId: <String, dynamic>{
            'algorithm_step': AlgorithmSteps.startResponse.name,
            'values': [H.modPow(a1, N).toString(), H.modPow(a2, N).toString(), P.toString(), Q.toString()]
          }
        }
      });

      sendUpdate(body);
      state = ProtocolStateStatus.startResponseSent;
    } catch (e) {
      String err = e.toString();
      print('\x1B[31m$err\x1B[0m');
    }
  }

  /// może tylko ten z większym ID otrzymać (Alice)
  void aliceReceiveStartResponse(hB1, hB2, bobP_, bobQ_) {
    if (state != ProtocolStateStatus.startSent) {
      throw Exception("Invalid state");
    }

    print('\x1B[39maliceReceiveStartResponse:\x1B[0m');

    BigInt hB1_ = BigInt.parse(hB1);
    BigInt hB2_ = BigInt.parse(hB2);

    if (hB1_ == BigInt.one || hB2_ == BigInt.one) {
      return sendTerminate();
    }

    otherPartyP = BigInt.parse(bobP_);
    otherPartyQ = BigInt.parse(bobQ_);

    sharedM = hB1_.modPow(a1, N);
    sharedL = hB2_.modPow(a2, N);

    P = sharedL.modPow(a3, N);
    Q = H.modPow(a3, N) * sharedM.modPow(x, N);
    R = BigInt.from(Q / otherPartyQ).modPow(a2, N);

    if (otherPartyP == P || otherPartyQ == Q) {
      return sendTerminate();
    }

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.part2.name,
          'values': [P.toString(), Q.toString(), R.toString()]
        }
      }
    });

    sendUpdate(body);
    state = ProtocolStateStatus.part2Sent;
  }

  void bobReceivePart2(aliceP_, aliceQ_, aliceR_) {
    if (state != ProtocolStateStatus.startResponseSent) {
      throw Exception("Invalid state");
    }

    BigInt _aliceP_ = BigInt.parse(aliceP_);
    BigInt _aliceQ_ = BigInt.parse(aliceQ_);
    BigInt _aliceR_ = BigInt.parse(aliceR_);

    R = BigInt.from(_aliceQ_ / Q).modPow(a2, N);

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.finish.name,
          'values': [R.toString()]
        }
      }
    });

    sendUpdate(body);

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = _aliceR_.modPow(a2, BigInt.one) == BigInt.from(P / otherPartyP);
    print('\x1B[33mres:'+res.toString()+'\x1B[0m');
    resultToInterface(res);
    // Dodatkowo zresetować stan protokołu
  }

  void aliceFinish(bobR_) {
    if (state != ProtocolStateStatus.part2Sent) {
      throw Exception("Invalid state");
    }

    /// TODO:
    BigInt _bobR_ = BigInt.from(bobR_);

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = _bobR_.modPow(a2, N) == BigInt.from(P / otherPartyP);
    resultToInterface(res);
    // Dodatkowo zresetować stan protokołu
  }

  void receiveTerminate() {
    state = ProtocolStateStatus.init;
  }

  void sendTerminate() {
    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.terminate.name
        }
      }
    });

    sendUpdate(body);

    state = ProtocolStateStatus.init;

    /// ewentualnie wyzerować wartości
  }

  /// TODO: do
  BigInt randomFromZp() {
    // int maxInt = 9223372036854775807;
    int maxInt = 92;
    BigInt maxInt_ = BigInt.from(maxInt);
    double div = N / maxInt_;

    double res = Random().nextDouble() * maxInt + 1;
    BigInt res_ = BigInt.from(res.floor());

    return res_;
  }

  void sendUpdate(String body) {
    requestBody = body;
    requestData = [];
  }
}
