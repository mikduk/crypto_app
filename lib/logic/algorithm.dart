import 'dart:convert';
import 'dart:math';

/// p
int p = 2;
/// h
int h = 3;

enum ProtocolStateStatus {init, startSent, startResponseSent, part2Sent}
enum AlgorithmSteps {start, startResponse, part2, terminate}

class ProtocolState {
  // fields
  String otherClientId = "";
  String myClientId = "";
  String? x;

  int a1 = 1;

  /// randomFromZp()
  int a2 = 1;

  /// randomFromZp()
  int a3 = 1;

  /// randomFromZp()

  num? sharedM;
  num? sharedL;
  num? bobP;
  num? bobQ;

  ProtocolStateStatus state = ProtocolStateStatus.init;

  // constructor
  ProtocolState(String otherClientID, String myClientID, String position) {
    otherClientId = otherClientID;
    myClientId = myClientID;
    x = position;
  }

  // functions
  void aliceSendStart() {
    if (state != ProtocolStateStatus.init) {
      throw Exception("Invalid state");
    }

    /// zakładając że mamy tylko 2 użytkowników, zaczyna ten z większym id (Alice)
    if (myClientId == "" || otherClientId == "") {
      return;
    } else if (myClientId.compareTo(otherClientId) <= 0) {
      return;
    }

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.start.name,
          'values': [
            pow(h, a1) % p,
            pow(h, a2) % p,
          ]
        }
      }
    });

    // send_update(body);

    state = ProtocolStateStatus.startSent;
  }

  /// może tylko ten z mniejszym ID otrzymać (Bob)
  void bobReceiveStart(hA1, hA2) {
    if (state != ProtocolStateStatus.init) {
      throw Exception("Invalid state");
    }

    if (hA1 == 1 || hA2 == 1) {
      return sendTerminate();
    }

    num m = pow(hA1, a1) % p;
    num l = pow(hA2, a2) % p;
    bobP = pow(l, a3) % p;
    bobQ = pow(h, a3) * pow(m, x); // x mam jako string na razie

    sharedM = m;
    sharedL = l;

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.startResponse.name,
          'values': [
            pow(h, a1) % p,
            pow(h, a2) % p,
            bobP,
            bobQ
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

    num m = pow(hB1, a1) % p;
    num l = pow(hB2, a2) % p;
    aliceP = pow(l, a3) % p;
    num aliceQ = pow(h, a3) * pow(m, x); // x mam jako string na razie

    if (alice_P == bobP || aliceQ == bobQ) {
      return sendTerminate();
    }

    /// TODO: zrób magię z dostępnymi liczbami żeby znaleźć wynik

    String body = jsonEncode(<String, dynamic>{
      'my_id': myClientId,
      'send_messages': <String, dynamic>{
        otherClientId: <String, dynamic>{
          'algorithm_step': AlgorithmSteps.part2.name,
          'values': [
            pow(h, a1) % p,
            pow(h, a2) % p,
            bobP,
            bobQ
          ]
        }
      }
    });

    // send_update(body);

    state = ProtocolStateStatus.part2Sent;
  }

  void bobReceivePart2(aliceP_, aliceQ_) {
    if (state != ProtocolStateStatus.startResponseSent) {
      throw Exception("Invalid state");
    }

    /// TODO: zrób magie z aliceP, alice_Q, self.my_P i self.my_Q
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
}
