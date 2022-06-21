import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import '../constants/api_constants.dart';

Future<dynamic> leaveResponse(String id) async {
  bool error = false;
  ByteData data = await rootBundle.load('assets/certificates/client1.pfx');
  SecurityContext context = SecurityContext.defaultContext;
  context.useCertificateChainBytes(data.buffer.asUint8List());
  context.usePrivateKeyBytes(data.buffer.asUint8List());

  Response response = await post(
    Uri.parse(ApiConstants.urlLeave),
    headers: ApiConstants.headers,
    body: jsonEncode(<String, dynamic>{
      'my_id': id,
    }),
  ).catchError((err) {
    print(err);
    error = true;
  });

  if (!error) {
    print(response.statusCode);
    print(response.body);
  }

  return response;
}