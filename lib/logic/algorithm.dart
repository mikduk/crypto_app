import 'dart:convert';
import 'dart:math';

/// p
int p = 2;
/// h
int h = 3;

enum ProtocolStateStatus {init, startSent, startResponseSent, part2Sent}
enum AlgorithmSteps {start, startResponse, part2, finish, terminate}

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
  num? otherPartyP;
  num? otherPartyQ;

  num? P;
  num? Q;
  num? R;

  ProtocolStateStatus state = ProtocolStateStatus.init;

  bool? Function(bool?) resultToInterface = (res) => null;

  // constructor
  ProtocolState(String otherClientID, String myClientID, String position, bool? Function(bool?) setMyState) {
    otherClientId = otherClientID;
    myClientId = myClientID;
    x = position;
    resultToInterface = setMyState;
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
    P = pow(l, a3) % p;
    Q = pow(h, a3) * pow(m, x); // x mam jako string na razie

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

    sharedM = pow(hB1, a1) % p;
    sharedL = pow(hB2, a2) % p;

    P = pow(sharedL!, a3) % p;
    Q = pow(h, a3) * pow(sharedM!, x); // x mam jako string na razie
    R = pow(Q! / otherPartyQ!, a2);

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

    R = pow(Q! / aliceQ_, a2);

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
    bool res = pow(aliceR_, a2) == P! / otherPartyP!;
    resultToInterface(res);
    // Dodatkowo zresetować stan protokołu
  }

  void aliceFinish(bobR_) {
    if (state != ProtocolStateStatus.part2Sent) {
      throw Exception("Invalid state");
    }

    // Tutaj wynik, trzeba update na interfejs wtedy puścić
    bool res = pow(bobR_, a2) == P! / otherPartyP!;
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
}
