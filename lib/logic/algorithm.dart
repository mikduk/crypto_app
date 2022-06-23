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

enum ProtocolStateStatus {init, startSent, startResponseSent, part2Sent}
enum AlgorithmSteps {start, startResponse, part2, finish, terminate}

class ProtocolState {
  // fields
  String otherClientId = "";
  String myClientId = "";
  late int x;

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

  void Function(bool?) resultToInterface = (bool? res){};

  // constructor
  ProtocolState(String otherClientID, String myClientID, Position position, bool? Function(bool?) setMyState) {
    otherClientId = otherClientID;
    myClientId = myClientID;
    x = GeoMapping.map(position);
    resultToInterface = setMyState;
    a1 = randomFromZp();
    a2 = randomFromZp();
    a3 = randomFromZp();
  }

  void startAlgorithm() async {
    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, String>{} // tutaj będzie obiekt
    });
    aliceSendStart();
    bobReceiveStart(1, 1);
    request(body);
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
        print("tech-print");
        print(responseObj["your_id"]);
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
        print("Hi, I'm Bob!");
        return;
      }

      print("Hi, I'm Alicia!");

      String body = jsonEncode(<String, dynamic>{
        'my_id': myClientId,
        'send_messages': <String, dynamic>{
          otherClientId: <String, dynamic>{
            'algorithm_step': AlgorithmSteps.start.name,
            'values': [
              H.modPow(a1, N),
              H.modPow(a2, N),
            ]
          }
        }
      });

      // send_update(body);

      state = ProtocolStateStatus.startSent;
    } catch (e) {
      String err = e.toString();
      print('\x1B[33m$err\x1B[0m');
    }
  }

  /// może tylko ten z mniejszym ID otrzymać (Bob)
  void bobReceiveStart(hA1, hA2) {
    if (state != ProtocolStateStatus.init) {
      print("I am further");
      throw Exception("Invalid state");
    }

    print("Bob official introduce");

    if (hA1 == 1 || hA2 == 1) {
      return sendTerminate();
    }

    BigInt m = hA1.modPow(a1, N);
    BigInt l = hA2.modPow(a2, N);
    P = l.modPow(a3, N);
    Q = H.modPow(a3, BigInt.one) * m.pow(x);

    sharedM = m;
    sharedL = l;

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.startResponse.name,
          'values': [
            H.modPow(a1, N),
            H.modPow(a2, N),
            P,
            Q
          ]
        }
      }
    });

    // send_update(body);

    state = ProtocolStateStatus.startResponseSent;
  }

  /// może tylko ten z większym ID otrzymać (Alice)
  void aliceReceiveStartResponse(hB1, hB2, bobP_, bobQ_) {
    if (state != ProtocolStateStatus.startSent) {
      throw Exception("Invalid state");
    }

    if (hB1 == 1 || hB2 == 1) {
      return sendTerminate();
    }

    otherPartyP = bobP_;
    otherPartyQ = bobQ_;

    sharedM = BigInt.from(hB1).modPow(a1, N);
    sharedL = BigInt.from(hB2).modPow(a2, N);

    P = sharedL.modPow(a3, N);
    Q = H.modPow(a3, BigInt.one) * sharedM.pow(x); // x mam jako string na razie
    R = BigInt.from(Q/otherPartyQ).modPow(a2, BigInt.one);

    if (otherPartyP == P || otherPartyQ == Q) {
      return sendTerminate();
    }

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.part2.name,
          'values': [
            P,
            Q,
            R
          ]
        }
      }
    });

    // send_update(body);

    state = ProtocolStateStatus.part2Sent;
  }

  void bobReceivePart2(aliceP_, aliceQ_, aliceR_) {
    if (state != ProtocolStateStatus.startResponseSent) {
      throw Exception("Invalid state");
    }

    BigInt _aliceR_ = BigInt.from(aliceR_);

    R = BigInt.from(aliceQ_ / Q).modPow(a2, BigInt.one);

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.finish.name,
          'values': [
            R
          ]
        }
      }
    });

    // send_update(body);

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = _aliceR_.modPow(a2, BigInt.one) == BigInt.from(P/otherPartyP);
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
    bool res = _bobR_.modPow(a2, BigInt.one) == BigInt.from(P/otherPartyP);
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

    // send_update(body);

    state = ProtocolStateStatus.init;

    /// ewentualnie wyzerować wartości
  }

  /// TODO: do
  BigInt randomFromZp() {
    return BigInt.one;
  }
}
