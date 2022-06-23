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
final BigInt N = BigInt.parse('0xFFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF');
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
    print('\x1B[34mAlgorithm (\"${state.name}\")\x1B[0m');
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
          print('\x1B[37mI\'m waiting for Bob...\x1B[0m');
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
          if (requestData.length == 1) {
            aliceFinish(requestData[0]);
          } else {
            print('\x1B[37mI\'m waiting for Bob...\x1B[0m');
          }
        break;
    }
    request(requestBody);
    Future.delayed(const Duration(seconds: 2), startAlgorithm);
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
      if (response.statusCode == 200) {
        dynamic responseObj = jsonDecode(response.body);
        bool _hasData = false;
        String? _step;
        List? _value;
        try {
          _step = responseObj["inbox"][otherClientId]["algorithm_step"];
          _value = (responseObj["inbox"][otherClientId]["values"]);
          _hasData = true;
        } catch (e) {
          // print("-");
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

      print('\x1B[37mHi, I\'m Alice!\x1B[0m');

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
      print('\x1B[33mAlice 1/3 [aliceSendStart]\x1B[0m');
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

      print('\x1B[33mBob 1/2 [bobReceiveStart]\x1B[0m');
      print("Bob official introduce");

      BigInt _hA1 = BigInt.parse(hA1);
      BigInt _hA2 = BigInt.parse(hA2);

      if (_hA1 == BigInt.one || _hA2 == BigInt.one) {
        return sendTerminate();
      }

      BigInt m = _hA1.modPow(a1, N);
      BigInt l = _hA2.modPow(a2, N);
      P = l.modPow(a3, N);
      Q = ( H.modPow(a3, N) * m.modPow(x, N) ) % N;

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
    Q = (H.modPow(a3, N) * sharedM.modPow(x, N)) % N;

    R = (((Q * otherPartyQ.modInverse(N)) % N).modPow(a2, N));

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

    print('\x1B[33mAlice 2/3 [aliceReceiveStartResponse]\x1B[0m');
  }

  void bobReceivePart2(aliceP_, aliceQ_, aliceR_) {
    if (state != ProtocolStateStatus.startResponseSent) {
      throw Exception("Invalid state");
    }

    BigInt _aliceP_ = BigInt.parse(aliceP_);
    BigInt _aliceQ_ = BigInt.parse(aliceQ_);
    BigInt _aliceR_ = BigInt.parse(aliceR_);

    R = (((_aliceQ_ * Q.modInverse(N))%N).modPow(a2, N));
    otherPartyP = _aliceP_;

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

    print('\x1B[33mBob 2/2 [BobReceivePart2]\x1B[0m');

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = _aliceR_.modPow(a2, N) == (otherPartyP * P.modInverse(N)) % N;
    print('\x1B[36mWYNIK: $res\x1B[0m');
    resultToInterface(res);
    // Dodatkowo zresetować stan protokołu
  }

  void aliceFinish(bobR_) {
    if (state != ProtocolStateStatus.part2Sent) {
      throw Exception("Invalid state");
    }

    BigInt _bobR_ = BigInt.parse(bobR_);

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = _bobR_.modPow(a2, N) == (P * otherPartyP.modInverse(N)) % N;
    print('\x1B[33mAlice 3/3 [aliceFinish]\x1B[0m');
    print('\x1B[36mWYNIK: $res\x1B[0m');
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
    int maxInt = 9223372036854775807;
    maxInt = min(N.toInt(), maxInt);

    double res = Random().nextDouble() * maxInt + 1;
    BigInt res_ = BigInt.from(res.floor());

    return res_;
  }

  void sendUpdate(String body) {
    requestBody = body;
    requestData = [];
  }
}
